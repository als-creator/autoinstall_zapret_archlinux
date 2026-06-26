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
FWTYPE=nftables
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
NFQWS_PORTS_TCP=80,443,50000-50099
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
--filter-tcp=80,443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --dpi-desync-ttl=4 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-fake-tls-mod=rnd,rndsni --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new ^
--filter-udp=80,443  --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --dpi-desync-ttl=4 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt""


# none,ipset,hostlist,autohostlist
MODE_FILTER=hostlist

# openwrt only : donttouch,none,software,hardware
FLOWOFFLOAD=none

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
IFACE_LAN=enp37s0
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
GETLIST=get_refilter_domains.sh
EOF

sudo tee /opt/zapret/ipset/zapret-hosts-user.txt >/dev/null <<'EOF'
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
EOF

sudo systemctl enable --now zapret.service || sudo systemctl start zapret.service || true

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
