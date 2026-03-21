#!/bin/bash
set -euo pipefail

# Запрещаем запуск от root
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "Не запускайте скрипт от root." >&2
  exit 1
fi

# Проверка наличия sudo
if ! command -v sudo >/dev/null 2>&1; then
  echo "sudo не установлен, установите его." >&2
  exit 1
fi

# Установка yay из AUR, если не найден
if ! command -v yay >/dev/null 2>&1; then
  echo "yay не найден — собираю из AUR..."
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  cd "$tmpdir"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  # makepkg требует прав пользователя (не root). makepkg -si попытается установить пакеты через pacman; если нужна интерактивность --noconfirm используется.
  makepkg -si --noconfirm
  cd -
fi

# Установка zapret, если не установлен (через pacman/yay)
if ! pacman -Qs ^zapret-git >/dev/null 2>&1; then
  echo "Устанавливаю zapret-git через yay..."
  yay -Sy --noconfirm zapret-git
fi

# Создаем директории если их нет (используем sudo)
sudo mkdir -p /opt/zapret/ipset /opt/zapret/files

# Конфиг zapret
sudo tee /opt/zapret/config >/dev/null <<'EOF'
FWTYPE=nftables
SET_MAXELEM=522288
IPSET_OPT="hashsize 262144 maxelem $SET_MAXELEM"
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
NFQWS_PORTS_TCP=80,443
NFQWS_PORTS_UDP=443,50000-65535
NFQWS_TCP_PKT_OUT=$((6+AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_TCP_PKT_IN=3
NFQWS_UDP_PKT_OUT=$((6+AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_UDP_PKT_IN=0
NFQWS_OPT="
--filter-udp=443 --hostlist=\"/opt/zapret/ipset/zapret-hosts-user.txt\" --dpi-desync=fake,split2 --dpi-desync-repeats=10 --dpi-desync-udplen-increment=15 --dpi-desync-udplen-pattern=0xCAFEBABE --dpi-desync-fake-quic=\"/opt/zapret/files/fake/quic_initial_www_google_com.bin\" --new ^
--filter-udp=50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-udp=50000-65535 --hostlist=\"/opt/zapret/ipset/ipset-discord.txt\" --dpi-desync=fake,disorder2 --dpi-desync-any-protocol --dpi-desync-cutoff=n5 --dpi-desync-repeats=10 --new ^
--filter-tcp=80 --hostlist=\"/opt/zapret/ipset/zapret-hosts-user.txt\" --dpi-desync=fake,disorder2 --dpi-desync-autottl=4 --dpi-desync-fooling=badseq --new ^
--filter-tcp=443 --hostlist=\"/opt/zapret/ipset/zapret-hosts-user.txt\" --dpi-desync=split --dpi-desync-split-pos=3 --dpi-desync-autottl=4 --dpi-desync-repeats=10 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=\"/opt/zapret/files/fake/tls_clienthello_www_google_com.bin\" "
MODE_FILTER=autohostlist
FLOWOFFLOAD=auto
INIT_APPLY_FW=1
DISABLE_IPV6=1
EOF

# Настройка доменов
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

# Включение и запуск сервиса zapret (проверяем существование systemd unit)
if systemctl --user --type=service --all >/dev/null 2>&1; then
  # Если пользовательские unit существуют, попробуем системный запуск
  sudo systemctl enable --now zapret.service || sudo systemctl start zapret.service || true
else
  sudo systemctl enable --now zapret.service || sudo systemctl start zapret.service || true
fi

echo "zapret успешно установлен, сервис запущен (если unit существует)."
echo "Настройки: /opt/zapret/config"
echo "Домены: /opt/zapret/ipset/zapret-hosts-user.txt"
echo "Документация: https://github.com/bol-van/zapret"

# Показать статус сервиса (не прерывать выполнение при ошибке)
sudo systemctl status zapret.service || true

exit 0
