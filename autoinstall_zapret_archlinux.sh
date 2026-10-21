#!/bin/bash
set -euo pipefail

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "Не запускайте скрипт от root." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo не установлен, установите его." >&2
  exit 1
fi

# --block-quic: блокировать UDP 443 (REJECT), чтобы браузер шёл по TCP через zapret
BLOCK_QUIC="no"
for a in "$@"; do
  [ "$a" = "--block-quic" ] && BLOCK_QUIC="yes"
done

# ---------------------------------------------------------------------------
# Удаление: --remove | --off | --uninstall
# Снимает сервис, юниты и правила, стирает каталог целиком (включая списки и
# бэкапы). Настройки byedpi не трогает.
# ---------------------------------------------------------------------------
case " ${*:-} " in
*" --remove "*|*" --off "*|*" --uninstall "*)
    ZDIR=/opt/zapret
    echo "=== Удаление zapret ==="
    sudo systemctl disable --now zapret 2>/dev/null || true
    sudo systemctl disable --now zapret2 2>/dev/null || true
    sudo systemctl disable --now zapret2-list-update.timer 2>/dev/null || true
    sudo systemctl disable --now zapret-quic 2>/dev/null || true
    sudo rm -f /etc/systemd/system/zapret.service \
               /etc/systemd/system/zapret2.service \
               /etc/systemd/system/zapret2-list-update.service \
               /etc/systemd/system/zapret2-list-update.timer \
               /etc/systemd/system/zapret-quic.service
    sudo systemctl daemon-reload 2>/dev/null || true
    # nft-таблица (если zapret создавал её) и цепочки ZAPRET_* в iptables
    sudo nft delete table inet zapret 2>/dev/null || true
    for c in $(sudo iptables-save 2>/dev/null | sed -n 's/^-A \(ZAPRET[^ ]*\).*/\1/p' | sort -u || true); do
        for ch in OUTPUT POSTROUTING PREROUTING INPUT; do
            sudo iptables -t mangle -D "$ch" -j "$c" 2>/dev/null || true
        done
        sudo iptables -t mangle -F "$c" 2>/dev/null || true
        sudo iptables -t mangle -X "$c" 2>/dev/null || true
    done
    for c in ZAPRET_QUIC; do
        sudo iptables -t filter -D OUTPUT -j "$c" 2>/dev/null || true
        sudo iptables -t filter -F "$c" 2>/dev/null || true
        sudo iptables -t filter -X "$c" 2>/dev/null || true
    done
    sudo rm -rf "$ZDIR" /etc/zapret /etc/zapret2
    if pgrep -x nfqws >/dev/null 2>&1; then
        echo "[WARN] nfqws ещё запущен — остановите: sudo systemctl stop zapret"
    fi
    echo "Удалено: $ZDIR, юниты, правила. Списки и их .bak тоже (каталог стёрт)."
    exit 0
    ;;
esac

# Создание файла исключений, если его нет
EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
if [ ! -f "$EXCLUDE_FILE" ]; then
  echo "Создаю файл исключений: $EXCLUDE_FILE"
  sudo mkdir -p /opt/zapret/ipset
  sudo touch "$EXCLUDE_FILE"
  sudo chown zapret:zapret "$EXCLUDE_FILE"
  sudo chmod 644 "$EXCLUDE_FILE"
  sudo tee "$EXCLUDE_FILE" >/dev/null <<'EOF'
# Файл исключений для zapret
# Сюда можно добавлять домены и IP-адреса, которые НЕ должны обрабатываться zapret
# Формат: один домен/IP на строку
# Примеры:
# google.com
# 192.168.1.0/24
# bank.example.com
# 8.8.8.8
EOF
fi

if ! command -v yay >/dev/null 2>&1; then
  echo "yay не найден — собираю из AUR..."
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  cd "$tmpdir"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd -
fi

if ! pacman -Qq zapret-git >/dev/null 2>&1; then
  echo "Устанавливаю zapret-git через yay..."
  yay -Sy --noconfirm zapret-git
fi

sudo mkdir -p /opt/zapret/ipset /opt/zapret/files

sudo tee /opt/zapret/config >/dev/null <<'EOF'
# this file is included from init scripts
# change values here

# can help in case /tmp has not enough space
#TMPDIR=/opt/zapret/tmp

# redefine user for zapret daemons. required on Keenetic
#WS_USER=nobody

# override firewall type : iptables,nftables,ipfw
FWTYPE=iptables
# nftables only : set this to 0 to use pre-nat mode. default is post-nat.
# pre-nat mode disables some bypass techniques for forwarded traffic but allows to see client IP addresses in debug log
#POSTNAT=0

# options for ipsets
# maximum number of elements in sets. also used for nft sets
SET_MAXELEM=522288
# too low hashsize can cause memory allocation errors on low RAM systems , even if RAM is enough
# too large hashsize will waste lots of RAM
IPSET_OPT="hashsize 262144 maxelem $SET_MAXELEM"
# dynamically generate additional ip. $1 = ipset/nfset/table name
#IPSET_HOOK="/etc/zapret.ipset.hook"

# options for ip2net. "-4" or "-6" auto added by ipset create script
IP2NET_OPT4="--prefix-length=22-30 --v4-threshold=3/4"
IP2NET_OPT6="--prefix-length=56-64 --v6-threshold=5"
# options for auto hostlist
AUTOHOSTLIST_RETRANS_THRESHOLD=3
AUTOHOSTLIST_FAIL_THRESHOLD=3
AUTOHOSTLIST_FAIL_TIME=60
# 1 = debug autohostlist positives to ipset/zapret-hosts-auto-debug.log
AUTOHOSTLIST_DEBUGLOG=0

# number of parallel threads for domain list resolves
MDIG_THREADS=30

# ipset/*.sh can compress large lists
GZIP_LISTS=1
# command to reload ip/host lists after update
# comment or leave empty for auto backend selection : ipset or ipfw if present
# on BSD systems with PF no auto reloading happens. you must provide your own command
# set to "-" to disable reload
#LISTS_RELOAD="pfctl -f /etc/pf.conf"

# mark bit used by nfqws to prevent loop
DESYNC_MARK=0x40000000
DESYNC_MARK_POSTNAT=0x20000000

TPWS_SOCKS_ENABLE=0
# tpws socks listens on this port on localhost and LAN interfaces
TPPORT_SOCKS=987
# use <HOSTLIST> and <HOSTLIST_NOAUTO> placeholders to engage standard hostlists and autohostlist in ipset dir
# hostlist markers are replaced to empty string if MODE_FILTER does not satisfy
# <HOSTLIST_NOAUTO> appends ipset/zapret-hosts-auto.txt as normal list
TPWS_SOCKS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --split-tls=sni --disorder <HOSTLIST>
"

TPWS_ENABLE=0
TPWS_PORTS=80,443
# use <HOSTLIST> and <HOSTLIST_NOAUTO> placeholders to engage standard hostlists and autohostlist in ipset dir
# hostlist markers are replaced to empty string if MODE_FILTER does not satisfy
# <HOSTLIST_NOAUTO> appends ipset/zapret-hosts-auto.txt as normal list
TPWS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --split-tls=sni --disorder <HOSTLIST>
"

NFQWS_ENABLE=1
# redirect outgoing traffic with connbytes limiter applied in both directions.
NFQWS_PORTS_TCP=80,443
NFQWS_PORTS_UDP=443,50000-65535
# PKT_OUT means connbytes dir original
# PKT_IN means connbytes dir reply
# this is --dpi-desync-cutoff=nX kernel mode implementation for linux. it saves a lot of CPU.
NFQWS_TCP_PKT_OUT=$((6+$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_TCP_PKT_IN=3
NFQWS_UDP_PKT_OUT=$((6+$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_UDP_PKT_IN=0
# redirect outgoing traffic without connbytes limiter and incoming with connbytes limiter
# normally it's needed only for stateless DPI that matches every packet in a single TCP session
# typical example are plain HTTP keep alives
# this mode can be very CPU consuming. enable with care !
#NFQWS_PORTS_TCP_KEEPALIVE=80
#NFQWS_PORTS_UDP_KEEPALIVE=
# use <HOSTLIST> and <HOSTLIST_NOAUTO> placeholders to engage standard hostlists and autohostlist in ipset dir
# hostlist markers are replaced to empty string if MODE_FILTER does not satisfy
# <HOSTLIST_NOAUTO> appends ipset/zapret-hosts-auto.txt as normal list
NFQWS_OPT="
--filter-udp=443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="/opt/zapret/files/fake/quic_initial_www_google_com.bin" --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new ^
--filter-udp=50000-65535  --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new ^
--filter-tcp=443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,split --dpi-desync-autottl=2 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new ^
--filter-tcp=443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=multisplit --dpi-desync-split-pos=1,midsld,sniext --dpi-desync-split-seqovl=1 --dpi-desync-fooling=badseq,md5sig --dpi-desync-repeats=6 --dpi-desync-autottl=2 --dpi-desync-fake-tls="/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt""
# none,ipset,hostlist,autohostlist
MODE_FILTER=autohostlist

# openwrt only : donttouch,none,software,hardware
FLOWOFFLOAD=donttouch

# openwrt: specify networks to be treated as LAN. default is "lan"
#OPENWRT_LAN="lan lan2 lan3"
# openwrt: specify networks to be treated as WAN. default wans are interfaces with default route
#OPENWRT_WAN4="wan vpn"
#OPENWRT_WAN6="wan6 vpn6"

# for routers based on desktop linux and macos. has no effect in openwrt.
# CHOOSE LAN and optinally WAN/WAN6 NETWORK INTERFACES
# or leave them commented if its not router
# it's possible to specify multiple interfaces like this : IFACE_LAN="eth0 eth1 eth2"
# if IFACE_WAN6 is not defined it take the value of IFACE_WAN
#IFACE_LAN=
#IFACE_WAN=
#IFACE_WAN6="ipsec0 wireguard0 he_net"

# should start/stop command of init scripts apply firewall rules ?
# not applicable to openwrt with firewall3+iptables
INIT_APPLY_FW=1
# firewall apply hooks
#INIT_FW_PRE_UP_HOOK="/etc/firewall.zapret.hook.pre_up"
#INIT_FW_POST_UP_HOOK="/etc/firewall.zapret.hook.post_up"
#INIT_FW_PRE_DOWN_HOOK="/etc/firewall.zapret.hook.pre_down"
#INIT_FW_POST_DOWN_HOOK="/etc/firewall.zapret.hook.post_down"

# do not work with ipv4
#DISABLE_IPV4=1
# do not work with ipv6
DISABLE_IPV6=1

# select which init script will be used to get ip or host list
# possible values : get_user.sh get_antizapret.sh get_combined.sh get_reestr.sh get_hostlist.sh
# comment if not required
#GETLIST=
EOF

if [ -f /opt/zapret/ipset/zapret-hosts-user.txt ] && [ "$KEEP_LISTS" != "yes" ]; then
    sudo cp -p /opt/zapret/ipset/zapret-hosts-user.txt "/opt/zapret/ipset/zapret-hosts-user.txt.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null \
        || sudo cp /opt/zapret/ipset/zapret-hosts-user.txt "/opt/zapret/ipset/zapret-hosts-user.txt.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    log_warn "Список доменов обновляется из скрипта, предыдущий сохранён в .bak-<дата>"
elif [ -f /opt/zapret/ipset/zapret-hosts-user.txt ]; then
    log_warn "Список уже есть и задан --keep-lists, не перезаписан: /opt/zapret/ipset/zapret-hosts-user.txt"
fi

sudo tee /opt/zapret/ipset/zapret-hosts-user.txt >/dev/null <<'EOF'
# --- МИНИМУМ: rutor / rutracker / nnm-club / youtube ---
# Rutor
rutor.info
rutor.is
# Rutracker
rutracker.org
rutracker.cc
# NNM-Club
nnmclub.to
nnmclub.me
# YouTube (включая CDN-поддомены)
youtube.com
googlevideo.com
ggpht.com
ytimg.com
yt.be
youtu.be
googleadservices.com
gvt1.com
youtube-nocookie.com
youtube-ui.l.google.com
youtubeembeddedplayer.googleapis.com
youtube.googleapis.com
youtubei.googleapis.com
jnn-pa.googleapis.com
yt-video-upload.l.google.com
wide-youtube.l.google.com
play.google.com
accounts.google.com
youtubekids.com
fonts.googleapis.com
googleads.g.doubleclick.net
# YouTube: apex-ы часто без A-записи, но нужны для матчинга поддоменов
gstatic.com
googleusercontent.com
l.google.com
1e100.net
m.youtube.com
img.youtube.com
yt3.googleusercontent.com
yt3.ggpht.com
yt4.ggpht.com
youtube.ru
youtube.com
googlevideo.com
ggpht.com
ytimg.com
yt.be
youtu.be
googleadservices.com
gvt1.com
youtube-nocookie.com
youtube-ui.l.google.com
youtubeembeddedplayer.googleapis.com
youtube.googleapis.com
youtubei.googleapis.com
jnn-pa.googleapis.com
yt-video-upload.l.google.com
wide-youtube.l.google.com
play.google.com
accounts.google.com
youtubekids.com
fonts.googleapis.com
googleads.g.doubleclick.net
news.google.com
igcdn-photos-e-a.akamaihd.net
instagramstatic.com
instagram.com
www.instagram.com
cdninstagram.com
www.cdninstagram.com
facebook.com
www.facebook.com
fbcdn.net
www.fbcdn.net
fburl.com
fbsbx.com
twitter.com
twimg.com
t.co
x.com
rutor.info
rutor.is
nnmclub.to
rutracker.org
rutracker.cc
discord.com
discord.co
discord.app
discord.gg
discord.dev
discord.new
discordapp.com
discordapp.io
discordapp.net
discordcdn.com
discordstatus.com
discord.media
dis.gd
discord-attachments-uploads-prd.storage.googleapis.com
cloudflare-ech.com
cloudflare.com
1.1.1.1
amazon.com
amazonaws.com
ntc.party
torproject.org
meduza.io
te-st.org
# --- Заблокированные сервисы и медиа ---------------------------------------
# Проверено: без desync не открываются (000), с zapret работают.
signal.org
www.signal.org
svoboda.org
www.svoboda.org
currenttime.tv
www.currenttime.tv
novayagazeta.eu
www.novayagazeta.eu
ovdinfo.org
www.ovdinfo.org
EOF

sudo systemctl enable --now zapret.service || sudo systemctl start zapret.service || true

# ---------------------------------------------------------------------------
# Блокировка QUIC (UDP 443) — только по --block-quic.
#
# Сам zapret умеет обходить блокировку QUIC (--filter-udp=443 + fake-quic),
# поэтому по умолчанию ничего не блокируем. Флаг нужен, когда fake не помогает
# и HTTP/3 всё равно висит: быстрый REJECT заставляет браузер идти по TCP.
# ---------------------------------------------------------------------------
setup_block_quic(){
  [ "$BLOCK_QUIC" = "yes" ] || return 0
  if ! command -v iptables >/dev/null 2>&1; then
    echo "[WARN] iptables не найден — блокировка QUIC пропущена" >&2
    return 0
  fi
  sudo tee /etc/systemd/system/zapret-quic.service >/dev/null <<'EOF'
[Unit]
Description=Block QUIC (UDP 443) so browsers use TCP through zapret
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -t filter -N ZAPRET_QUIC 2>/dev/null || true; iptables -t filter -F ZAPRET_QUIC; iptables -t filter -A ZAPRET_QUIC -p udp --dport 443 -m owner ! --uid-owner 0 -j REJECT --reject-with icmp-port-unreachable; iptables -t filter -C OUTPUT -j ZAPRET_QUIC 2>/dev/null || iptables -t filter -A OUTPUT -j ZAPRET_QUIC'
ExecStop=/bin/sh -c 'iptables -t filter -D OUTPUT -j ZAPRET_QUIC 2>/dev/null || true; iptables -t filter -F ZAPRET_QUIC 2>/dev/null || true; iptables -t filter -X ZAPRET_QUIC 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload >/dev/null 2>&1
  sudo systemctl enable --now zapret-quic.service >/dev/null 2>&1 || true
  echo "[OK] QUIC (UDP 443) заблокирован: zapret-quic.service"
}
setup_block_quic

# ---------------------------------------------------------------------------
# Проверка минимального набора доменов
# ---------------------------------------------------------------------------
verify_min_domains(){
    command -v curl >/dev/null 2>&1 || { echo "curl не найден, пропускаю проверку"; return 0; }
    min_domains="rutracker.org nnmclub.to www.youtube.com i.ytimg.com yt3.googleusercontent.com discord.com"
    echo
    echo "Минимальный набор доменов:"
    for h in $min_domains; do
        code=$(curl -k -sS -m 8 -o /dev/null -w '%{http_code}' "https://$h/" 2>/dev/null)
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            printf '  %-30s OK (%s)\n' "$h" "$code"
            continue
        fi
        inlist=no
        grep -qE "^[[:space:]]*$(printf '%s' "$h" | sed 's/\./\\./g')([[:space:]]*\$)" /opt/zapret/ipset/zapret-hosts-user.txt 2>/dev/null && inlist=yes
        if [ "$inlist" = no ]; then
            printf '  %-30s FAIL (домена нет в zapret-hosts-user.txt)\n' "$h"
        else
            printf '  %-30s FAIL (домен в списке, но не открывается — вероятна блокировка по IP)\n' "$h"
        fi
    done
}

verify_min_domains

cat <<'EOF'

════════════════════════════════════════════════════════════════════
                    ИНФОРМАЦИЯ О ЗАВИСИМОСТЯХ
════════════════════════════════════════════════════════════════════

sudo - Необходим для выполнения команд с повышенными привилегиями.
git - Необходим для клонирования репозитория.
libnetfilter_queue - Требуется для фильтрации сетевых пакетов при использовании NFQUEUE, TPWS, TPWS+.

Проверка:
sudo -v
git --version
pacman -Q libnetfilter_queue

════════════════════════════════════════════════════════════════════
                      УПРАВЛЕНИЕ СЕРВИСОМ
════════════════════════════════════════════════════════════════════

Запуск сервиса:
sudo systemctl start zapret.service

Остановка сервиса:
sudo systemctl stop zapret.service

Перезагрузка сервиса:
sudo systemctl restart zapret.service

Проверка статуса:
sudo systemctl status zapret.service

Просмотр логов:
sudo journalctl -u zapret.service -f

Отключение автозагрузки:
sudo systemctl disable zapret.service

Включение автозагрузки:
sudo systemctl enable zapret.service

════════════════════════════════════════════════════════════════════
                    КОНФИГУРАЦИЯ ZAPRET
════════════════════════════════════════════════════════════════════

Основной конфиг:
  /opt/zapret/config

Список доменов для блокировки:
  /opt/zapret/ipset/zapret-hosts-user.txt

Список исключений (что НЕ блокировать):
  /opt/zapret/ipset/zapret-hosts-user-exclude.txt

После редактирования конфигов:
sudo systemctl restart zapret.service

════════════════════════════════════════════════════════════════════
                    ФАЙЛ ИСКЛЮЧЕНИЙ (zapret-hosts-user-exclude.txt)
════════════════════════════════════════════════════════════════════

Этот файл содержит список доменов и IP-адресов, которые НЕ должны
обрабатываться zapret. Это полезно для:

1. Банковских сайтов (чтобы не блокировались платежи)
2. Корпоративных сетей (внутренние ресурсы)
3. Локальных сервисов (192.168.x.x, localhost)
4. Важных государственных сайтов
5. VPN-серверов

Формат файла:
- Один домен/IP на строку
- Комментарии начинаются с #
- Поддерживаются маски подсетей (например, 192.168.1.0/24)

Примеры:
# Банковские сайты
sberbank.ru
tinkoff.ru
alfabank.ru

# Локальная сеть
192.168.1.0/24
10.0.0.1

# Важные государственные сайты
kremlin.ru
government.ru

После добавления новых исключений:
sudo systemctl restart zapret.service

════════════════════════════════════════════════════════════════════
                    УДАЛЕНИЕ ZAPRET
════════════════════════════════════════════════════════════════════

sudo pacman -Rsn --noconfirm zapret-git

EOF

exit 0
