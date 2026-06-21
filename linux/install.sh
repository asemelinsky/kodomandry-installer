#!/usr/bin/env bash
# Kodomandry Minecraft Installer (Linux)
# PoC v0.1 — portable Prism Launcher AppImage + Temurin JRE 21 + Kodomandry modpack
#
# Дистрибутиви: Fedora 38+, Ubuntu 22.04+, Debian 12+, Arch, Manjaro, openSUSE
# Usage:  bash install.sh
#         або: chmod +x install.sh && ./install.sh

set -euo pipefail

# --- Константи ---
APP_NAME="Kodomandry"
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_NAME"
PRISM_DIR="$INSTALL_DIR/PrismLauncher"
JAVA_DIR="$INSTALL_DIR/java21"
TEMP_DIR="/tmp/$APP_NAME-install"
INSTANCE_NAME="Kodomandry 1.21.1"
INSTANCE_DIR="$PRISM_DIR/instances/Kodomandry"

PRISM_API="https://api.github.com/repos/Diegiwg/PrismLauncher-Cracked/releases/latest"
MODPACK_URL="https://github.com/asemelinsky/kodomandy-modpack/releases/latest/download/kodomandy-server2.mrpack"

# Arch detection — для AppImage і Temurin
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        PRISM_ASSET_PATTERN='PrismLauncher-Linux-x86_64\.AppImage$'
        JAVA_ARCH="x64"
        ;;
    aarch64|arm64)
        PRISM_ASSET_PATTERN='PrismLauncher-Linux-aarch64\.AppImage$'
        JAVA_ARCH="aarch64"
        ;;
    *)
        echo "✗ Непідтримувана архітектура: $ARCH"
        echo "  Підтримуються: x86_64, aarch64"
        exit 1
        ;;
esac
JAVA_API="https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$JAVA_ARCH&image_type=jre&os=linux&vendor=eclipse"

# --- Кольори (з detection чи stdout — tty) ---
if [[ -t 1 ]]; then
    CYAN="\033[36m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; DIM="\033[2m"; RESET="\033[0m"
else
    CYAN=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi
step() { echo; echo -e "${CYAN}==> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}!${RESET} $1"; }

# --- GUI-діалоги: zenity (GNOME) → kdialog (KDE) → fallback на termial ---
# Діти не завжди читають Terminal, тож критичні повідомлення показуємо у вікнах.
UI_TOOL=""
if command -v zenity >/dev/null 2>&1; then
    UI_TOOL="zenity"
elif command -v kdialog >/dev/null 2>&1; then
    UI_TOOL="kdialog"
fi

ui_alert() {
    # $1 = title  $2 = message
    case "$UI_TOOL" in
        zenity)  zenity --info --title="$1" --text="$2" --width=460 >/dev/null 2>&1 || true ;;
        kdialog) kdialog --title "$1" --msgbox "$2" >/dev/null 2>&1 || true ;;
        *)       echo; echo -e "${CYAN}■ $1${RESET}"; echo "  $2"; echo ;;
    esac
}
ui_error() {
    case "$UI_TOOL" in
        zenity)  zenity --error --title="$1" --text="$2" --width=460 >/dev/null 2>&1 || true ;;
        kdialog) kdialog --title "$1" --error "$2" >/dev/null 2>&1 || true ;;
        *)       echo; echo -e "${RED}✗ $1${RESET}"; echo "  $2"; echo ;;
    esac
}
# ui_ask "prompt" [default]  →  stdout = введений текст; exit 1 = Cancel
ui_ask() {
    local prompt="$1" default="${2:-}"
    case "$UI_TOOL" in
        zenity)
            zenity --entry --title="$APP_NAME Minecraft" --text="$prompt" \
                --entry-text="$default" --width=460 2>/dev/null
            ;;
        kdialog)
            kdialog --title "$APP_NAME Minecraft" --inputbox "$prompt" "$default" 2>/dev/null
            ;;
        *)
            echo "$prompt" >&2
            local input=""
            read -r -p "  → " input
            if [[ -z "$input" ]]; then
                return 1
            fi
            printf '%s' "$input"
            ;;
    esac
}

# --- Trap для помилок ---
trap 'rc=$?; ln=$LINENO; ui_error "Kodomandry — помилка установки" "Щось пішло не так на рядку $ln (код $rc). Зроби скрін цього вікна і покажи вчителю."; echo; echo -e "${RED}✗ ПОМИЛКА на рядку $ln${RESET}"; read -r -p "Натисни Enter щоб закрити..."; exit 1' ERR

# ui_confirm "title" "message" — питання Так/Ні. exit 0 = Yes, 1 = No.
ui_confirm() {
    case "$UI_TOOL" in
        zenity)
            zenity --question --title="$1" --text="$2" \
                --ok-label="Так, встановити" --cancel-label="Ні, я сам" \
                --width=460 >/dev/null 2>&1
            ;;
        kdialog)
            kdialog --title "$1" --yesno "$2" >/dev/null 2>&1
            ;;
        *)
            echo; echo -e "${CYAN}■ $1${RESET}"; echo "  $2"; echo
            local ans=""
            read -r -p "  Встановити автоматично? [Y/n] " ans
            ans=${ans:-Y}
            [[ "$ans" =~ ^[Yy]$ ]]
            ;;
    esac
}

# --- Перевірка залежностей з auto-install ---
# Збирає всі відсутні системні утиліти + perl-модулі у один список,
# показує діалог із підказкою, пропонує встановити через sudo одним пакетом.
check_deps() {
    local missing_cmds=()
    local missing_pkgs=()

    # Системні утиліти
    for cmd in curl perl tar unzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_cmds+=("$cmd")
            missing_pkgs+=("$cmd")
        fi
    done

    # Perl JSON::PP — у більшості дистрибутивів є з perl-core, але інколи окремо.
    # Назва пакета різна на різних дистрибутивах, тому формуємо нижче по pkgmgr.
    local need_json_pp=0
    if command -v perl >/dev/null 2>&1; then
        if ! perl -MJSON::PP -e1 >/dev/null 2>&1; then
            need_json_pp=1
            missing_cmds+=("perl-JSON::PP")
        fi
    fi

    # Нічого не бракує
    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        return 0
    fi

    # Детект package manager + назва JSON-PP пакета для нього
    local pkgmgr="" install_cmd="" json_pp_pkg=""
    if command -v dnf >/dev/null 2>&1; then
        pkgmgr="dnf"; install_cmd="sudo dnf install -y"; json_pp_pkg="perl-JSON-PP"
    elif command -v apt >/dev/null 2>&1; then
        pkgmgr="apt"; install_cmd="sudo apt install -y"; json_pp_pkg="libjson-pp-perl"
    elif command -v pacman >/dev/null 2>&1; then
        pkgmgr="pacman"; install_cmd="sudo pacman -S --needed --noconfirm"; json_pp_pkg="perl"
    elif command -v zypper >/dev/null 2>&1; then
        pkgmgr="zypper"; install_cmd="sudo zypper install -y"; json_pp_pkg="perl-JSON-PP"
    fi

    # Замінити placeholder perl-JSON::PP на правильний пакет
    if [[ $need_json_pp -eq 1 ]]; then
        local new_pkgs=()
        for p in "${missing_pkgs[@]}"; do
            new_pkgs+=("$p")
        done
        new_pkgs+=("$json_pp_pkg")
        missing_pkgs=("${new_pkgs[@]}")
    fi

    local full_cmd="$install_cmd ${missing_pkgs[*]}"
    if [[ "$pkgmgr" == "apt" ]]; then
        full_cmd="sudo apt update && $full_cmd"
    fi

    # Якщо pkgmgr не визначений — не можемо нічого зробити
    if [[ -z "$pkgmgr" ]]; then
        ui_error "Бракує системних утиліт" "Не знайдено: ${missing_cmds[*]}. Встанови їх через package manager твого дистрибутиву і запусти інсталятор знову."
        echo -e "${RED}✗ Бракує: ${missing_cmds[*]}${RESET}"
        echo "  Не зміг детектити package manager — встанови вручну."
        exit 1
    fi

    echo -e "${YELLOW}!${RESET} Бракує: ${missing_cmds[*]}"
    echo "  Команда для встановлення: $full_cmd"
    echo

    # Питаємо чи встановлювати автоматично
    local msg="Для роботи інсталятора бракує: ${missing_cmds[*]}.\n\nКоманда:\n$full_cmd\n\nПотрібно ввести пароль адміністратора (sudo).\n\nВстановити автоматично зараз?"
    if ui_confirm "Бракує системних утиліт" "$msg"; then
        echo "  Запуск: $full_cmd"
        # Не використовуємо || щоб ERR trap зловив помилку. Якщо sudo впаде —
        # юзер побачить причину (не той пароль, мережа, тощо) і зможе виконати вручну.
        # Виконуємо у термін explicit щоб sudo міг попросити пароль.
        if [[ "$pkgmgr" == "apt" ]]; then
            sudo apt update
            sudo apt install -y "${missing_pkgs[@]}"
        elif [[ "$pkgmgr" == "dnf" ]]; then
            sudo dnf install -y "${missing_pkgs[@]}"
        elif [[ "$pkgmgr" == "pacman" ]]; then
            sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
        elif [[ "$pkgmgr" == "zypper" ]]; then
            sudo zypper install -y "${missing_pkgs[@]}"
        fi

        # Re-check — якщо все одно бракує, помилка
        local still_missing=()
        for cmd in curl perl tar unzip; do
            command -v "$cmd" >/dev/null 2>&1 || still_missing+=("$cmd")
        done
        if [[ $need_json_pp -eq 1 ]] && ! perl -MJSON::PP -e1 >/dev/null 2>&1; then
            still_missing+=("perl-JSON::PP")
        fi

        if [[ ${#still_missing[@]} -gt 0 ]]; then
            ui_error "Установка пакетів не повна" "Після установки все одно бракує: ${still_missing[*]}.\n\nПеревір лог вище і встанови вручну:\n\n$full_cmd"
            echo -e "${RED}✗ Все одно бракує після sudo: ${still_missing[*]}${RESET}"
            exit 1
        fi
        echo -e "  ${GREEN}✓${RESET} Залежності встановлено"
    else
        ui_error "Установку не можна продовжити" "Без цих пакетів інсталятор не може працювати.\n\nВстанови вручну:\n\n$full_cmd\n\nі запусти знову."
        echo -e "${RED}✗ Користувач відмовився встановити залежності${RESET}"
        echo "  Команда: $full_cmd"
        exit 1
    fi
}
check_deps

# --- Утиліти ---
download() {
    local url="$1" out="$2"
    curl -L --fail --retry 3 --retry-delay 2 --progress-bar -o "$out" "$url"
}

# --- 0. Детект install vs update + welcome-діалог ---
# Update-режим: AppImage + акаунт уже є → користувача не смикаємо
# по Java/нікнейму, а просто тягнемо свіжі моди.
PRISM_APPIMAGE_PROBE="$PRISM_DIR/PrismLauncher.AppImage"
ACCOUNTS_PROBE="$PRISM_DIR/accounts.json"
if [[ -x "$PRISM_APPIMAGE_PROBE" && -f "$ACCOUNTS_PROBE" ]]; then
    IS_UPDATE=1
    ui_alert "Kodomandry — оновлення" "Знайдено попередню установку. Зараз скачаються оновлені моди й конфіги сервера (~1-2 хв). Натисни OK щоб продовжити."
else
    IS_UPDATE=0
    ui_alert "Kodomandry — установка" "Зараз буде встановлено Minecraft, Java і моди (~500 МБ). Потрібно 3-10 хвилин та стабільний інтернет. НЕ закривай Terminal до завершення — коли буде готово, ти побачиш зелене вікно 'ВСТАНОВЛЕНО'."
fi

# --- 1. Підготовка ---
step "Kodomandry Installer PoC v0.1 (Linux $ARCH) [$([[ $IS_UPDATE -eq 1 ]] && echo update || echo install)]"
echo "Install dir: $INSTALL_DIR"
echo "UI tool:     ${UI_TOOL:-terminal-fallback}"

mkdir -p "$INSTALL_DIR" "$TEMP_DIR" "$PRISM_DIR"

# --- 2. Prism Launcher AppImage ---
step "Перевірка Prism Launcher"

PRISM_APPIMAGE="$PRISM_DIR/PrismLauncher.AppImage"
NEEDS_DOWNLOAD=0
if [[ -x "$PRISM_APPIMAGE" ]]; then
    ok "Prism AppImage вже є"
else
    NEEDS_DOWNLOAD=1
fi

if [[ $NEEDS_DOWNLOAD -eq 1 ]]; then
    echo "  Завантаження інформації про реліз..."
    RELEASE=$(curl -fsSL -H "User-Agent: $APP_NAME" "$PRISM_API")
    ASSET_URL=$(echo "$RELEASE" | perl -MJSON::PP -0777 -ne '
my $d = decode_json($_);
for my $a (@{$d->{assets}}) {
    if ($a->{name} =~ /'"$PRISM_ASSET_PATTERN"'/) {
        print $a->{browser_download_url}; last;
    }
}')
    if [[ -z "$ASSET_URL" ]]; then
        echo "✗ Не знайдено Linux-AppImage у релізі (pattern: $PRISM_ASSET_PATTERN)"
        exit 1
    fi
    ASSET_NAME="${ASSET_URL##*/}"
    echo "  Версія: $ASSET_NAME"
    download "$ASSET_URL" "$PRISM_APPIMAGE"
    chmod +x "$PRISM_APPIMAGE"
    ok "Prism AppImage завантажено"
fi

# Перевірка FUSE — потрібен для запуску AppImage; fallback --appimage-extract-and-run
PRISM_RUN_FLAGS=""
if ! "$PRISM_APPIMAGE" --appimage-version >/dev/null 2>&1; then
    if [[ -e /dev/fuse ]] && command -v fusermount >/dev/null 2>&1; then
        :  # FUSE є — все добре
    else
        warn "FUSE не виявлено — Prism запуститься з --appimage-extract-and-run (повільніший старт)"
        PRISM_RUN_FLAGS="--appimage-extract-and-run"
    fi
fi

# Portable-режим — файл-маркер поруч з AppImage. У Prism Launcher portable.txt
# вмикає режим де всі дані (instances, accounts, configs) лежать у тій же
# теці що AppImage, а не у ~/.local/share/PrismLauncher/.
PORTABLE_FLAG="$PRISM_DIR/portable.txt"
touch "$PORTABLE_FLAG"

# Конфіг
PRISM_CFG="$PRISM_DIR/prismlauncher.cfg"
touch "$PRISM_CFG"
for kv in "AutoUpdate=false" "UpdateChannel=" "CheckForUpdates=false" "Language=uk_UA" "AnalyticsSeen=1"; do
    key="${kv%%=*}"
    if grep -q "^$key=" "$PRISM_CFG"; then
        # GNU sed (Linux) — без '' аргумента
        sed -i "s|^$key=.*|$kv|" "$PRISM_CFG"
    else
        echo "$kv" >> "$PRISM_CFG"
    fi
done
ok "Автооновлення вимкнено, мова uk_UA"

# --- 3. Java 21 ---
step "Перевірка Java 21"

JAVA_EXE=""

# Системна java — перевіримо чи 21+
if command -v java >/dev/null 2>&1; then
    SYSTEM_JAVA=$(command -v java)
    # Витягуємо major version. java -version пише у stderr.
    JV=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
    if [[ -n "$JV" && "$JV" -ge 21 ]]; then
        JAVA_EXE="$SYSTEM_JAVA"
        ok "Системна Java $JV знайдена: $JAVA_EXE"
    fi
fi

# Локальна java (від попередньої установки)
if [[ -z "$JAVA_EXE" && -d "$JAVA_DIR" ]]; then
    LOCAL=$(find "$JAVA_DIR" -name 'java' -type f -executable 2>/dev/null | head -1 || true)
    if [[ -n "$LOCAL" ]]; then
        JAVA_EXE="$LOCAL"
        ok "Локальна Java знайдена: $JAVA_EXE"
    fi
fi

# Завантажити Temurin
if [[ -z "$JAVA_EXE" ]]; then
    echo "  Java 21 не знайдена. Завантаження Temurin JRE 21 ($JAVA_ARCH)..."
    JRE_JSON=$(curl -fsSL -H "User-Agent: $APP_NAME" "$JAVA_API")
    JRE_URL=$(echo "$JRE_JSON" | perl -MJSON::PP -0777 -ne 'print decode_json($_)->[0]{binary}{package}{link}')
    JRE_NAME=$(echo "$JRE_JSON" | perl -MJSON::PP -0777 -ne 'print decode_json($_)->[0]{binary}{package}{name}')
    JRE_TAR="$TEMP_DIR/$JRE_NAME"
    download "$JRE_URL" "$JRE_TAR"

    mkdir -p "$JAVA_DIR"
    tar -xzf "$JRE_TAR" -C "$JAVA_DIR"

    LOCAL=$(find "$JAVA_DIR" -name 'java' -type f -executable 2>/dev/null | head -1)
    if [[ -n "$LOCAL" ]]; then
        JAVA_EXE="$LOCAL"
        chmod +x "$JAVA_EXE"
        ok "Java 21 встановлена: $JAVA_EXE"
    else
        echo "✗ java не знайдено після розпакування"
        exit 1
    fi
fi

# --- 3.5. Instance з модпаком ---
step "Створення збірки '$INSTANCE_NAME'"

MC_DIR="$INSTANCE_DIR/.minecraft"
MODS_DIR="$MC_DIR/mods"
mkdir -p "$INSTANCE_DIR" "$MC_DIR" "$MODS_DIR"

# Завантаження .mrpack ПЕРЕД конфігами — щоб версії NeoForge/Minecraft взяти
# з manifest. Якщо у модпаку бамп NeoForge — клієнт автоматично оновиться.
MRPACK="$TEMP_DIR/kodomandry.mrpack"
echo "  Завантаження модпаку..."
download "$MODPACK_URL" "$MRPACK"

MRPACK_DIR="$TEMP_DIR/mrpack"
rm -rf "$MRPACK_DIR"; mkdir -p "$MRPACK_DIR"
unzip -q "$MRPACK" -d "$MRPACK_DIR"

# Версії з manifest
NF_VERSION=$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{dependencies}{neoforge}' "$MRPACK_DIR/modrinth.index.json")
MC_VERSION=$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{dependencies}{minecraft}' "$MRPACK_DIR/modrinth.index.json")
if [[ -z "$NF_VERSION" || -z "$MC_VERSION" ]]; then
    echo "✗ Не зміг прочитати neoforge/minecraft з modrinth.index.json"
    exit 1
fi
ok "Версії з модпака: Minecraft $MC_VERSION + NeoForge $NF_VERSION"

# mmc-pack.json — ЗАВЖДИ регенеруємо, щоб update підхопив свіжу NeoForge
cat > "$INSTANCE_DIR/mmc-pack.json" <<EOF
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "$MC_VERSION" },
        { "uid": "net.neoforged", "version": "$NF_VERSION" }
    ],
    "formatVersion": 1
}
EOF

# instance.cfg — пишемо тільки якщо нема (не затирати user-tweaks пам'яті)
if [[ ! -f "$INSTANCE_DIR/instance.cfg" ]]; then
    cat > "$INSTANCE_DIR/instance.cfg" <<EOF
InstanceType=OneSix
OverrideMemory=true
MinMemAlloc=2048
MaxMemAlloc=4096
iconKey=default
name=$INSTANCE_NAME
notes=Server: 46.225.227.42:25566\nNeoForge $NF_VERSION
EOF
fi

# Sync: видалити старі моди, докачати нові
perl -MJSON::PP -0777 -e '
use strict; use warnings;
my ($idx_path, $mc_dir, $mods_dir) = @ARGV;
open(my $fh, "<", $idx_path) or die "$idx_path: $!";
my $idx = decode_json(do { local $/; <$fh> });

my %expected = map {; "$mc_dir/$_->{path}" => 1 } @{$idx->{files}};

my $removed = 0;
if (-d $mods_dir) {
    opendir(my $dh, $mods_dir) or die;
    for my $name (readdir $dh) {
        next unless $name =~ /\.jar$/;
        my $full = "$mods_dir/$name";
        if (!$expected{$full}) {
            unlink $full;
            print "    - видалено: $name\n";
            $removed++;
        }
    }
}

my $total = scalar @{$idx->{files}};
my ($downloaded, $skipped) = (0, 0);
my $i = 0;
for my $f (@{$idx->{files}}) {
    $i++;
    my $target = "$mc_dir/$f->{path}";
    my $name = $f->{path}; $name =~ s{.*/}{};
    my $dir = $target; $dir =~ s{/[^/]+$}{};
    system("mkdir", "-p", $dir) == 0 or die;
    if (-e $target) { $skipped++; next; }
    print "    [$i/$total] $name\n";
    system("curl", "-L", "--fail", "--retry", "3", "--progress-bar",
           "-o", $target, $f->{downloads}[0]) == 0
        or die "curl failed for $name";
    $downloaded++;
}
print "    +$downloaded нових, -$removed старих, $skipped без змін\n";
' "$MRPACK_DIR/modrinth.index.json" "$MC_DIR" "$MODS_DIR"
ok "Моди синхронізовано"

# Overrides — завжди перезаписуємо
if [[ -d "$MRPACK_DIR/overrides" ]]; then
    cp -R "$MRPACK_DIR/overrides/"* "$MC_DIR/" 2>/dev/null || true
    ok "Overrides (конфіги + servers.dat) оновлено"
fi

# --- 3.6. Офлайн-акаунт ---
ACCOUNTS_PATH="$PRISM_DIR/accounts.json"
step "Офлайн-акаунт"
if [[ -f "$ACCOUNTS_PATH" ]]; then
    ok "Акаунт вже налаштовано"
else
    echo "  Нікнейм буде видимий у грі та на сервері."
    NICK=""
    while [[ -z "$NICK" ]]; do
        INPUT=$(ui_ask "Придумай собі нікнейм для сервера. Його побачать інші гравці. 3-16 символів, тільки латиниця, цифри і _." "") || {
            ui_error "Установку скасовано" "Ти натиснув Скасувати. Без нікнейма грати не вийде. Запусти інсталятор ще раз коли будеш готовий."
            exit 1
        }
        INPUT="${INPUT// /}"
        if [[ "$INPUT" =~ ^[A-Za-z0-9_]{3,16}$ ]]; then
            NICK="$INPUT"
        else
            ui_alert "Невалідний нікнейм" "Нікнейм має бути 3-16 символів, тільки латиниця (A-Z, a-z), цифри (0-9) і знак підкреслення (_). Спробуй ще раз."
        fi
    done
    echo "  Нікнейм: $NICK"

    perl -MDigest::MD5=md5_hex -MJSON::PP -e '
use strict; use warnings;
my ($nick, $out) = @ARGV;
my $hex = md5_hex("OfflinePlayer:$nick");
# v3 UUID: set version=3 and RFC4122 variant
substr($hex, 12, 1) = "3";
my $v = hex(substr($hex, 16, 1));
substr($hex, 16, 1) = sprintf("%x", ($v & 0x3) | 0x8);
my @chars = ("a".."f", 0..9);
my $client = join "", map { $chars[rand @chars] } 1..32;
my $data = {
    formatVersion => 3,
    accounts => [{
        active => JSON::PP::true,
        type   => "Offline",
        profile => {
            id    => $hex,
            name  => $nick,
            capes => [],
            skin  => { id => "", url => "", variant => "" },
        },
        ygg => {
            iat   => time(),
            token => "0",
            extra => { clientToken => $client, userName => $nick },
        },
    }],
};
open(my $fh, ">:encoding(UTF-8)", $out) or die "$out: $!";
print $fh JSON::PP->new->utf8(0)->pretty->indent_length(4)->encode($data);
' "$NICK" "$ACCOUNTS_PATH"
    ok "Акаунт '$NICK' створено"
fi

# --- 4. Launcher wrapper + ярлики ---
# AppImage запускається з -d флагом який вказує Prism шукати дані у нашому
# PRISM_DIR (інакше portable.txt теоретично теж працює, але -d надійніше і
# дозволяє переміщати теку). Wrapper-скрипт ставить ENV і виконує AppImage.
step "Створення ярлика"

WRAPPER="$INSTALL_DIR/launch-kodomandry.sh"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# Auto-generated launcher for Kodomandry Minecraft
# Запускає Prism Launcher AppImage у portable-режимі з нашим data-dir.
exec "$PRISM_APPIMAGE" $PRISM_RUN_FLAGS -d "$PRISM_DIR" "\$@"
EOF
chmod +x "$WRAPPER"

# Іконка: спробуємо взяти з ../assets/, інакше fallback на дефолтну
ICON_PATH="$INSTALL_DIR/kodomandry.png"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for src in "$SCRIPT_DIR/icon.png" "$SCRIPT_DIR/../assets/icon.png"; do
    if [[ -f "$src" ]]; then
        cp "$src" "$ICON_PATH"
        break
    fi
done
[[ -f "$ICON_PATH" ]] || ICON_PATH=""

# Створюємо .desktop файл
DESKTOP_CONTENT="[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME Minecraft
GenericName=Minecraft Launcher
Comment=Kodomandry Minecraft — Prism Launcher з модпаком
Exec=$WRAPPER
${ICON_PATH:+Icon=$ICON_PATH}
Terminal=false
Categories=Game;
StartupNotify=true
StartupWMClass=PrismLauncher"

# 1) Меню програм (XDG applications)
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS_DIR"
DESKTOP_MENU="$APPS_DIR/kodomandry-minecraft.desktop"
echo "$DESKTOP_CONTENT" > "$DESKTOP_MENU"
chmod +x "$DESKTOP_MENU"
ok "Додано у меню програм: $DESKTOP_MENU"

# Update desktop database (якщо є)
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
fi

# 2) Робочий стіл — через XDG (підтримує українську локаль ~/Стільниця)
DESKTOP_PATH=""
if command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_PATH=$(xdg-user-dir DESKTOP 2>/dev/null || true)
fi
# Fallback варіанти
if [[ -z "$DESKTOP_PATH" || ! -d "$DESKTOP_PATH" ]]; then
    for candidate in "$HOME/Desktop" "$HOME/Стільниця" "$HOME/Рабочий стол"; do
        if [[ -d "$candidate" ]]; then
            DESKTOP_PATH="$candidate"
            break
        fi
    done
fi

if [[ -n "$DESKTOP_PATH" && -d "$DESKTOP_PATH" ]]; then
    DESKTOP_FILE="$DESKTOP_PATH/$APP_NAME Minecraft.desktop"
    echo "$DESKTOP_CONTENT" > "$DESKTOP_FILE"
    chmod +x "$DESKTOP_FILE"

    # GNOME 42+ потребує metadata::trusted=true щоб іконка не показувала
    # "?" поверх і запускалась з подвійного кліку. KDE/XFCE ігнорують.
    if command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP_FILE" "metadata::trusted" true >/dev/null 2>&1 || true
    fi
    ok "Ярлик на робочому столі: $DESKTOP_FILE"
else
    warn "Не знайдено робочий стіл — ярлик тільки у меню програм"
fi

# --- 5. Прибирання ---
step "Прибирання"
rm -rf "$TEMP_DIR"
ok "Готово"

# --- 6. Наступні кроки ---
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ВСТАНОВЛЕНО! Наступні кроки:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "  1. Запусти '$APP_NAME Minecraft' (з робочого столу або з меню програм)"
echo
echo "  2. Якщо з'явиться діалог 'A new version is available' —"
echo "     натисни 'No' / 'Skip' (НЕ оновлювати!)"
echo
echo "  3. Обери '$INSTANCE_NAME' -> Launch"
echo "     Акаунт і сервер 46.225.227.42:25566 уже налаштовані"
echo
echo "  Java:  $JAVA_EXE"
echo "  Prism: $PRISM_APPIMAGE"
echo

if [[ $IS_UPDATE -eq 1 ]]; then
    ui_alert "Kodomandry — оновлено ✓" "Моди й конфіги сервера оновлено. Запусти ярлик «Kodomandry Minecraft» — і можна грати. Натисни OK щоб закрити це вікно."
else
    ui_alert "Kodomandry — встановлено ✓" "Готово! Запусти ярлик «Kodomandry Minecraft» з робочого столу або меню програм. Якщо Prism запитає 'A new version is available' — натискай No. Далі обери збірку 'Kodomandry 1.21.1' і тисни Launch. Натисни OK щоб закрити це вікно."
fi

# Запропонувати запустити (тільки у termal-режимі — інакше юзер вже клацнув OK у вікні)
if [[ -t 0 ]]; then
    read -r -p "Запустити Prism Launcher зараз? [Y/n] " LAUNCH
    LAUNCH=${LAUNCH:-Y}
    if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
        # nohup + & — щоб Prism не помер коли закриється Terminal
        nohup "$WRAPPER" >/dev/null 2>&1 &
        disown
        ok "Prism запущено"
    fi
fi
