# Kodomandry Installer (Linux)

Один скрипт `install.sh` — і у учня є повна збірка Minecraft з модпаком, Java 21,
портативним Prism Launcher та готовим offline-акаунтом. Повторний запуск
працює як оновлення.

## Підтримувані системи

- **Fedora 38+** (Workstation, KDE Plasma)
- **Ubuntu 22.04+**, **Debian 12+**, **Linux Mint**
- **Arch / Manjaro / EndeavourOS**
- **openSUSE Leap 15.5+**, **Tumbleweed**
- Архітектури: **x86_64** і **aarch64** (ARM)

## Як запустити (для учня)

1. Завантажити архів `kodomandry-installer-linux.zip` з
   https://github.com/asemelinsky/kodomandry-installer/releases/latest

2. Розпакувати → відкрити Terminal у теці зі скриптом → виконати:

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. Чекати 3-10 хвилин (моди ~500 МБ).
4. Запускати з ярлика **Kodomandry Minecraft** на робочому столі або з меню програм.

## Що скрипт робить (один флоу — і установка, і оновлення)

1. `${XDG_DATA_HOME:-~/.local/share}/Kodomandry/` — кореневий install dir (XDG-compliant)
2. **Prism Launcher AppImage** з `Diegiwg/PrismLauncher-Cracked` GitHub release
   - x86_64 → `PrismLauncher-Linux-x86_64.AppImage`
   - aarch64 → `PrismLauncher-Linux-aarch64.AppImage`
   - `portable.txt` поруч → portable-режим (дані в нашій теці, не у `~/.local/share/PrismLauncher/`)
3. **Java 21**: спочатку перевіряємо системну (`java -version`), якщо нема або не 21+ — качаємо Temurin JRE 21 tarball з adoptium.net
4. Prism config: `Language=uk_UA`, вимкнене автооновлення
5. Створює instance **Kodomandry 1.21.1**:
   - читає Minecraft+NeoForge версії з `modrinth.index.json` модпаку (автоматичний бамп при апдейті модпаку)
   - синхронізує моди: видаляє непотрібні, докачує нові, пропускає співпадаючі
   - перезаписує `overrides/` (конфіги + `servers.dat` з адресою сервера)
6. Запит нікнейма → генерація offline-акаунта (UUID v3 з MD5 від `OfflinePlayer:<name>`)
7. Ярлики:
   - `~/.local/share/applications/kodomandry-minecraft.desktop` (меню програм)
   - `<XDG_DESKTOP>/Kodomandry Minecraft.desktop` (робочий стіл) — підтримує українську локаль `~/Стільниця`
8. Пропонує запустити Prism

## GUI vs Terminal-режим

Скрипт намагається показати критичні повідомлення (привітання, запит нікнейма,
помилки) через **zenity** (GNOME) або **kdialog** (KDE). Якщо жодного нема —
fallback на запити у Terminal.

Якщо ти запускаєш у headless-режимі (SSH без X11/Wayland), все одно працює:
запити йдуть у stdin/stdout.

## Залежності

Скрипт автоматично перевіряє наявність:

- `bash` (≥4.0)
- `curl`
- `perl` + `JSON::PP` (Perl модуль)
- `tar`, `unzip`

Якщо чогось бракує — скрипт покаже точну команду для встановлення під твій
дистрибутив.

Не вимагає `sudo` — все встановлюється у `~/.local/share/`.

## Troubleshooting

### `AppImage failed to mount` / `cannot mount AppImage`

AppImage потребує **FUSE**. На більшості сучасних дистрибутивів FUSE
встановлений за замовченням. Якщо ні:

- **Fedora:** `sudo dnf install -y fuse fuse-libs`
- **Ubuntu/Debian:** `sudo apt install -y libfuse2`
- **Arch:** `sudo pacman -S --needed fuse2`

Якщо ставити FUSE не хочеш — скрипт автоматично детектне і запустить AppImage
з прапором `--appimage-extract-and-run` (повільніший старт ~5с, але працює).

### Ярлик на робочому столі показує `?` поверх (GNOME 42+)

GNOME 42+ потребує позначки `metadata::trusted=true`. Скрипт ставить її
автоматично через `gio`. Якщо не спрацювало:

```bash
gio set ~/Стільниця/"Kodomandry Minecraft.desktop" metadata::trusted true
```

Перезавантаж Files / GNOME Shell.

### `perl: command not found` або `Can't locate JSON/PP.pm`

Деякі мінімальні установки не мають Perl з модулями. Встанови:

- **Fedora:** `sudo dnf install -y perl-JSON-PP`
- **Ubuntu/Debian:** `sudo apt install -y libjson-pp-perl`
- **Arch:** `sudo pacman -S --needed perl` (включає JSON::PP)

### Minecraft вилітає одразу після запуску

Перевір що драйвер GPU підтримує OpenGL 3.3+. На дуже старих ноутах
(2010-2014 з Intel HD Graphics):

```bash
MESA_GL_VERSION_OVERRIDE=3.3 ~/.local/share/Kodomandry/launch-kodomandry.sh
```

Або встанови свіжіший Mesa з репозиторіїв дистрибутиву.

## Re-run (оновлення модпаку)

Запусти `./install.sh` ще раз. Скрипт визначить, що Prism+акаунт вже є
(IS_UPDATE=1), пропустить запит нікнейма і Java, і просто синхронізує моди
зі свіжим `.mrpack` з GitHub.

## Деінсталяція

```bash
rm -rf ~/.local/share/Kodomandry
rm ~/.local/share/applications/kodomandry-minecraft.desktop
rm ~/Стільниця/"Kodomandry Minecraft.desktop"  # або ~/Desktop/
update-desktop-database ~/.local/share/applications/
```

## Файли

```
linux/
├── install.sh    головний скрипт (~560 рядків bash)
├── README.md     цей файл
└── icon.png      (опційно — або symlink на ../assets/)
```
