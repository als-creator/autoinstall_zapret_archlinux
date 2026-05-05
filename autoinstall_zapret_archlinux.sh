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
#POSTNAT=0

SET_MAXELEM=522288
IPSET_OPT="hashsize 262144 maxelem $SET_MAXELEM"
#IPSET_HOOK="/etc/zapret.ipset.hook"

IP2NET_OPT4="--prefix-length=22-30 --v4-threshold=3/4"
IP2NET_OPT6="--prefix-length=56-64 --v6-threshold=5"

AUTOHOSTLIST_RETRANS_THRESHOLD=3
AUTOHOSTLIST_FAIL_THRESHOLD=3
AUTOHOSTLIST_FAIL_TIME=60
AUTOHOSTLIST_DEBUGLOG=0

MDIG_THREADS=30

GZIP_LISTS=1

DESYNC_MARK=0x40000000
DESYNC_MARK_POSTNAT=0x20000000

TPWS_SOCKS_ENABLE=0
TPPORT_SOCKS=987
TPWS_SOCKS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --split-tls=sni --disorder <HOSTLIST>
"

TPWS_ENABLE=0
TPWS_PORTS=80,443
TPWS_OPT="
--filter-tcp=80 --methodeol <HOSTLIST> --new
--filter-tcp=443 --split-tls=sni --disorder <HOSTLIST>
"

NFQWS_ENABLE=1
NFQWS_PORTS_TCP=80,443,50000-50099
NFQWS_PORTS_UDP=443,50000-65535
NFQWS_TCP_PKT_OUT=$((6+$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_TCP_PKT_IN=3
NFQWS_UDP_PKT_OUT=$((6+$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_UDP_PKT_IN=0

NFQWS_OPT="
--filter-tcp=80,443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --dpi-desync-ttl=4 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-fake-tls-mod=rnd,rndsni --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new
--filter-udp=80,443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --dpi-desync-ttl=4 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt" --new
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --hostlist-exclude="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
"

MODE_FILTER=autohostlist
FLOWOFFLOAD=donttouch

INIT_APPLY_FW=1

DISABLE_IPV6=1
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
sms-activate.guru
onlinesim.io
ntc.party
cryptpad.fr
bbc.com
proton.me
protonvpn.com
tuta.com
prostovpn.org
torproject.org
mullvad.net
psiphon.ca
z-lib.io
singlelogin.cc
lordfilms.day
hd2.lordfilm-ru.net
lordfilm.llc
archive.org
web.archive.org
soundcloud.com
novayagazeta.eu
meduza.io
holod.media
moscowtimes.ru
roskomsvoboda.org
te-st.org
dept.one
idelreal.org
rferl.org
krymr.com
indigogobot.com
glaznews.com
bellingcat.com
cdn.hsmedia.ru
static.doubleclick.net
cdn.vigo.one
republic.ru
viber.com
signal.org
hrw.org
animego.org
escapefromtarkov.com
quora.com
rumble.com
wixmp.com
gifer.com
save4k.top
coursera.org
udemy.com
znanija.com
basis.gnulinux.pro
infra.gnulinux.pro
regexlearn.com
linkedin.com
www.linkedin.com
px.ads.linkedin.com
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

Список доменов:
  /opt/zapret/ipset/zapret-hosts-user.txt

После редактирования:
sudo systemctl restart zapret.service

════════════════════════════════════════════════════════════════════
                    УДАЛЕНИЕ ZAPRET
════════════════════════════════════════════════════════════════════

sudo pacman -Rsn --noconfirm zapret-git

EOF

exit 0
