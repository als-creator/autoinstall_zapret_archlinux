#!/bin/bash
set -e

# Запрещаем запуск от root
if [ "$EUID" -eq 0 ]; then
  echo "Не запускайте скрипт от root." >&2
  exit 1
fi

# Проверка наличия sudo
if ! command -v sudo &> /dev/null; then
  echo "sudo не установлен, установите его." >&2
  exit 1
fi

# Установка yay из AUR вручую если не найден
if ! command -v yay &> /dev/null; then
  echo "yay не найден — собираю из AUR..."
  cd /tmp
  [ -d yay ] && rm -rf yay
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
fi

# Установка zapret, если его нет
if ! pacman -Q zapret-git &> /dev/null; then
  yay -Sy --noconfirm zapret-git
fi

# Конфиг zapret
cat << EOF | sudo tee /opt/zapret/config > /dev/null
FWTYPE=nftables
SET_MAXELEM=522288
IPSET_OPT="hashsize 262144 maxelem \$SET_MAXELEM"
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
NFQWS_TCP_PKT_OUT=\$((6+\$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_TCP_PKT_IN=3
NFQWS_UDP_PKT_OUT=\$((6+\$AUTOHOSTLIST_RETRANS_THRESHOLD))
NFQWS_UDP_PKT_IN=0
NFQWS_OPT="
--filter-udp=443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="/opt/zapret/files/fake/quic_initial_www_google_com.bin" --new \
--filter-udp=50000-65535 --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new \
--filter-tcp=80 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new \
--filter-tcp=443 --hostlist="/opt/zapret/ipset/zapret-hosts-user.txt" --dpi-desync=fake,split --dpi-desync-autottl=2 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
"
MODE_FILTER=hostlist
FLOWOFFLOAD=auto
INIT_APPLY_FW=1
DISABLE_IPV6=1
EOF

# Настройка доменов
cat << EOF | sudo tee /opt/zapret/ipset/zapret-hosts-user.txt > /dev/null
youtube.com
googlevideo.com
google.com
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
EOF

# Включение и запуск сервиса zapret
sudo systemctl enable --now zapret

echo "zapret успешно установлен, сервис запущен для работы с пользовательским листом доменов"
echo "Правило из скрипта может не работать у вас, работа не гарантируется, изучайте документацию для настройки своего провайдера"
echo "Настройки можно изменить в /opt/zapret/config"
echo "Документация для настройки своего конфига github.com/bol-van/zapret"
echo "Настройку доменов можно производить в /opt/zapret/ipset/zapret-hosts-user.txt"
echo "sudo systemctl restart zapret для перезапуска"
echo "sudo systemctl start zapret для запуска"
echo "sudo systemctl status zapret для проверки статуса сервиса"
sudo systemctl status zapret
