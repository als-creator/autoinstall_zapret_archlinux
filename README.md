# 🛡 Скрипт для автоматической установки и настройки Zapret

Этот скрипт автоматизирует процесс установки и базовой настройки утилиты zapret, предназначен только для Arch Linux и его производных, использующих pacman или yay.

## Автоматическая установка

```bash
curl -fsSL https://raw.githubusercontent.com/als-creator/autoinstall_zapret_archlinux/main/autoinstall_zapret_archlinux.sh | sh

```

<details>
  <summary>Ориентировочно поддерживаемые дистры, проверялось на EndeavourOS и ArchLinux</summary>

- ArcoLinux
- Arch Linux
- Carli
- Alci
- Ariser
- EndeavourOS
- Garuda
- Manjaro
- RebornOS
- Archcraft
- CachyOS
- Archman
- Biglinux
- Artix
- ParchLinux
- StormOS
- Mabox
- ArchBang
- Crystal Linux
- Liya
- Bluestar Linux
- Calam-Arch-Installer

_Скрипт ориентирован на скачивание из репозитория ArchLinux пакета zapret-git через yay и установку готовых конфигов для yota, остальнгые провайдеры не проверялись. Если репозитории ArchLinux не менялись, проблем быть не должно. Для других дистров можно форкнуть и адаптировать под свой пакетный менеджер, предварительно проверив пути установки и конфиги._

</details>

---

## 🚀 Что делает скрипт

- **Проверка прав:** Скрипт проверяет, что он не запущен от имени root, так как это может привести к нежелательным последствиям.
- **Проверка sudo:** Убеждается в наличии прав sudo у текущего пользователя.
- **Установка yay:** Если менеджер пакетов yay не найден, скрипт автоматически клонирует его из AUR и устанавливает.
- **Установка zapret:** Использует yay для установки zapret-git из AUR.
- **Настройка zapret:** Создает или перезаписывает файл конфигурации `/opt/zapret/config` с преднастроенными параметрами.
- **Настройка списка доменов:** Создает или перезаписывает файл `/opt/zapret/ipset/zapret-hosts-user.txt` со списком популярных доменов.
- **Запуск сервиса:** Включает и запускает системный сервис zapret с помощью systemd.
- **Вывод статуса:** Отображает текущий статус сервиса zapret, чтобы вы могли убедиться в его успешном запуске.

---

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
 Редактирование: sudo nano /opt/zapret/config

Основные параметры:  
 • MODE - режим работы (NFQUEUE, TPWS, TPWS+, FAKE, etc)  
 • TPWS_PORT - порт для TPWS  
 • IPSET - набор IP адресов для обработки

Список доменов для блокировки:  
 /opt/zapret/ipset/zapret-hosts-user.txt  
 Редактирование: sudo nano /opt/zapret/ipset/zapret-hosts-user.txt

Формат: один домен на строку  
 Пример:  
 example.com  
 blocked.site  
 forbidden.net

sudo systemctl restart zapret.service

## Удаление zapret

Если zapret больше не требуется, выполните следующие команды:

```bash
su -c '
  if systemctl list-unit-files | grep -q "zapret.service"; then
    systemctl disable --now zapret.service
    rm /etc/systemd/system/zapret.service
    systemctl daemon-reload
  fi
  rm -rf /opt/zapret
  if dpkg -l | grep -q "libnetfilter_queue"; then
    apt-get remove -y libnetfilter_queue
  fi
'
```

То же самое в несколько команд:

Отключение автозагрузки:

```bash
sudo systemctl disable --now zapret.service
```

Удаление systemd unit:

```bash
sudo rm /etc/systemd/system/zapret.service
```

Перезагрузка systemd:

```bash
sudo systemctl daemon-reload
```

Удаление файлов zapret:

```bash
sudo rm -rf /opt/zapret
```

Удаление зависимостей (опционально):

```bash
sudo apt-get remove libnetfilter_queue
```

## Проверка зависимостей

Проверка наличия sudo:  
sudo -v

Проверка наличия git:  
git --version

Проверка наличия libnetfilter_queue:  
dpkg -l | grep libnetfilter

## Решение проблем

Если сервис не запускается, проверьте логи:  
sudo journalctl -u zapret.service -n 50

Если конфиг невалиден, проверьте синтаксис:  
cat /opt/zapret/config

[Наборы хостов и правил для перебора под своего провайдера](https://github.com/Snowy-Fluffy/zapret.cfgs)

Если доступа нет, проверьте права доступа:  
ls -la /opt/zapret/

## Лицензия

Используется лицензия из оригинального репозитория zapret.
