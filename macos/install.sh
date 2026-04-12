#!/usr/bin/env bash
# Kodomandry Minecraft Installer (macOS)
# PoC v0.1 — portable Prism Launcher + Temurin JRE 21
#
# Usage: bash install.sh
#        або: chmod +x install.sh && ./install.sh

set -euo pipefail

# --- Константи ---
APP_NAME="Kodomandry"
INSTALL_DIR="$HOME/Library/Application Support/$APP_NAME"
PRISM_DIR="$INSTALL_DIR/PrismLauncher"
JAVA_DIR="$INSTALL_DIR/java21"
TEMP_DIR="/tmp/$APP_NAME-install"

PRISM_API="https://api.github.com/repos/Diegiwg/PrismLauncher-Cracked/releases/latest"
# macOS universal tarball
PRISM_ASSET_PATTERN='PrismLauncher-macOS-.*\.tar\.gz$'

MODPACK_URL="https://github.com/asemelinsky/kodomandy-modpack/releases/latest/download/kodomandy-server2.mrpack"
INSTANCE_NAME="Kodomandry 1.21.1"
INSTANCE_DIR="$PRISM_DIR/instances/Kodomandry"

# Arch detection для Temurin
ARCH=$(uname -m)
case "$ARCH" in
    arm64) JAVA_ARCH="aarch64" ;;
    x86_64) JAVA_ARCH="x64" ;;
    *) echo "✗ Непідтримувана архітектура: $ARCH"; exit 1 ;;
esac
JAVA_API="https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$JAVA_ARCH&image_type=jre&os=mac&vendor=eclipse"

# --- Кольори ---
CYAN="\033[36m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; DIM="\033[2m"; RESET="\033[0m"
step() { echo; echo -e "${CYAN}==> $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}!${RESET} $1"; }

# --- Trap для помилок ---
trap 'echo; echo -e "${RED}✗ ПОМИЛКА на рядку $LINENO${RESET}"; read -r -p "Натисни Enter щоб закрити..."; exit 1' ERR

# --- Утиліти ---
download() {
    local url="$1" out="$2"
    curl -L --fail --retry 3 --retry-delay 2 --progress-bar -o "$out" "$url"
}

# --- 1. Підготовка ---
step "Kodomandry Installer PoC v0.1 (macOS $ARCH)"
echo "Install dir: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR" "$TEMP_DIR"

# --- 2. Prism Launcher ---
step "Перевірка Prism Launcher"

PRISM_EXEC="$PRISM_DIR/PrismLauncher.app/Contents/MacOS/prismlauncher"
if [[ -x "$PRISM_EXEC" ]]; then
    ok "Prism вже встановлено"
else
    echo "  Завантаження інформації про реліз..."
    RELEASE=$(curl -fsSL -H "User-Agent: $APP_NAME" "$PRISM_API")
    ASSET_URL=$(echo "$RELEASE" | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
pat = re.compile('$PRISM_ASSET_PATTERN')
for a in data['assets']:
    if pat.search(a['name']):
        print(a['browser_download_url']); break
")
    if [[ -z "$ASSET_URL" ]]; then
        echo "✗ Не знайдено macOS-ассет у релізі"; exit 1
    fi
    ASSET_NAME="${ASSET_URL##*/}"
    echo "  Версія asset: $ASSET_NAME"
    TARBALL="$TEMP_DIR/$ASSET_NAME"
    download "$ASSET_URL" "$TARBALL"

    echo "  Розпакування..."
    mkdir -p "$PRISM_DIR"
    tar -xzf "$TARBALL" -C "$PRISM_DIR"

    if [[ ! -x "$PRISM_EXEC" ]]; then
        # Можливо .app у корені архіву
        APP_FOUND=$(find "$PRISM_DIR" -maxdepth 3 -name 'PrismLauncher.app' -print -quit)
        if [[ -n "$APP_FOUND" && "$APP_FOUND" != "$PRISM_DIR/PrismLauncher.app" ]]; then
            mv "$APP_FOUND" "$PRISM_DIR/"
        fi
    fi

    if [[ -x "$PRISM_EXEC" ]]; then
        ok "Prism встановлено"
    else
        echo "✗ PrismLauncher.app не знайдено після розпакування"; exit 1
    fi

    # Зняти карантин (щоб Gatekeeper не блокував)
    xattr -dr com.apple.quarantine "$PRISM_DIR/PrismLauncher.app" 2>/dev/null || true
fi

# Portable-режим — файл-маркер
PORTABLE_FLAG="$PRISM_DIR/PrismLauncher.app/Contents/MacOS/portable.txt"
touch "$PORTABLE_FLAG"

# Конфіг
PRISM_CFG="$PRISM_DIR/PrismLauncher.app/Contents/MacOS/prismlauncher.cfg"
touch "$PRISM_CFG"
for kv in "AutoUpdate=false" "UpdateChannel=" "CheckForUpdates=false" "Language=uk_UA" "AnalyticsSeen=1"; do
    key="${kv%%=*}"
    if grep -q "^$key=" "$PRISM_CFG"; then
        # sed -i '' для macOS
        sed -i '' "s|^$key=.*|$kv|" "$PRISM_CFG"
    else
        echo "$kv" >> "$PRISM_CFG"
    fi
done
ok "Автооновлення вимкнено, мова uk_UA"

# --- 3. Java 21 ---
step "Перевірка Java 21"

JAVA_EXE=""
# Системна java
if command -v java >/dev/null 2>&1; then
    VER=$(java -version 2>&1 | head -1)
    if echo "$VER" | grep -qE 'version "(21|21\.)'; then
        JAVA_EXE="$(command -v java)"
        ok "Системна Java 21 знайдена: $JAVA_EXE"
    fi
fi

# Локальна java
if [[ -z "$JAVA_EXE" && -d "$JAVA_DIR" ]]; then
    LOCAL=$(find "$JAVA_DIR" -name 'java' -type f -perm +111 | head -1 || true)
    if [[ -n "$LOCAL" ]]; then
        JAVA_EXE="$LOCAL"
        ok "Локальна Java знайдена: $JAVA_EXE"
    fi
fi

# Завантажити Temurin
if [[ -z "$JAVA_EXE" ]]; then
    echo "  Java 21 не знайдена. Завантаження Temurin JRE 21 ($JAVA_ARCH)..."
    JRE_JSON=$(curl -fsSL -H "User-Agent: $APP_NAME" "$JAVA_API")
    JRE_URL=$(echo "$JRE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['binary']['package']['link'])")
    JRE_NAME=$(echo "$JRE_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['binary']['package']['name'])")
    JRE_TAR="$TEMP_DIR/$JRE_NAME"
    download "$JRE_URL" "$JRE_TAR"

    mkdir -p "$JAVA_DIR"
    tar -xzf "$JRE_TAR" -C "$JAVA_DIR"

    LOCAL=$(find "$JAVA_DIR" -name 'java' -type f | head -1)
    if [[ -n "$LOCAL" ]]; then
        JAVA_EXE="$LOCAL"
        chmod +x "$JAVA_EXE"
        ok "Java 21 встановлена: $JAVA_EXE"
    else
        echo "✗ java не знайдено після розпакування"; exit 1
    fi
fi

# --- 3.5. Instance з модпаком ---
step "Створення збірки '$INSTANCE_NAME'"

MC_DIR="$INSTANCE_DIR/.minecraft"
MODS_DIR="$MC_DIR/mods"

if [[ -f "$INSTANCE_DIR/mmc-pack.json" ]]; then
    ok "Збірка вже існує — пропускаю"
else
    mkdir -p "$INSTANCE_DIR" "$MC_DIR" "$MODS_DIR"

    cat > "$INSTANCE_DIR/mmc-pack.json" <<'EOF'
{
    "components": [
        { "important": true, "uid": "net.minecraft", "version": "1.21.1" },
        { "uid": "net.neoforged", "version": "21.1.216" }
    ],
    "formatVersion": 1
}
EOF

    cat > "$INSTANCE_DIR/instance.cfg" <<EOF
InstanceType=OneSix
OverrideMemory=true
MinMemAlloc=2048
MaxMemAlloc=4096
iconKey=default
name=$INSTANCE_NAME
notes=Server: 46.225.227.42:25566\nNeoForge 21.1.216
EOF
    ok "Конфіги створено"

    # Завантаження .mrpack
    MRPACK="$TEMP_DIR/kodomandry.mrpack"
    echo "  Завантаження модпаку..."
    download "$MODPACK_URL" "$MRPACK"

    # Розпакування (mrpack = zip)
    MRPACK_DIR="$TEMP_DIR/mrpack"
    rm -rf "$MRPACK_DIR"; mkdir -p "$MRPACK_DIR"
    unzip -q "$MRPACK" -d "$MRPACK_DIR"

    # Парсинг index і завантаження модів
    python3 - "$MRPACK_DIR/modrinth.index.json" "$MC_DIR" <<'PYEOF'
import json, os, subprocess, sys
idx_path, mc_dir = sys.argv[1], sys.argv[2]
with open(idx_path) as f:
    idx = json.load(f)
total = len(idx["files"])
for i, f in enumerate(idx["files"], 1):
    target = os.path.join(mc_dir, f["path"])
    name = os.path.basename(f["path"])
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target):
        print(f"    [{i}/{total}] {name} — пропуск")
        continue
    url = f["downloads"][0]
    print(f"    [{i}/{total}] {name}")
    subprocess.check_call([
        "curl", "-L", "--fail", "--retry", "3", "--progress-bar",
        "-o", target, url
    ])
PYEOF
    ok "Моди завантажено"

    # Overrides
    if [[ -d "$MRPACK_DIR/overrides" ]]; then
        cp -R "$MRPACK_DIR/overrides/"* "$MC_DIR/" 2>/dev/null || true
        ok "Конфіги/ресурси застосовано"
    fi
fi

# --- 4. Ярлик в /Applications (symlink) ---
step "Створення ярлика"
APP_LINK="/Applications/$APP_NAME Minecraft.app"
if [[ -e "$APP_LINK" || -L "$APP_LINK" ]]; then
    rm -f "$APP_LINK"
fi
ln -s "$PRISM_DIR/PrismLauncher.app" "$APP_LINK" 2>/dev/null || {
    # Якщо /Applications захищений без sudo — кладемо на Desktop
    APP_LINK="$HOME/Desktop/$APP_NAME Minecraft.app"
    rm -f "$APP_LINK"
    ln -s "$PRISM_DIR/PrismLauncher.app" "$APP_LINK"
    warn "Немає доступу до /Applications — ярлик на робочому столі"
}
ok "Ярлик: $APP_LINK"

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
echo "  1. Запусти '$APP_NAME Minecraft' ($APP_LINK)"
echo "     Перший раз: правий клік -> Open (через Gatekeeper)"
echo
echo "  2. Якщо з'явиться діалог 'A new version is available' —"
echo "     натисни 'No' / 'Skip' (НЕ оновлювати!)"
echo
echo "  3. Додай офлайн-акаунт (один раз):"
echo "     Accounts -> Manage Accounts -> Add Offline -> нікнейм (латиницею)"
echo
echo "  4. Обери '$INSTANCE_NAME' -> Launch"
echo "     Сервер 46.225.227.42:25566 вже в списку Multiplayer"
echo
echo "  Java: $JAVA_EXE"
echo "  Prism: $PRISM_EXEC"
echo

read -r -p "Запустити Prism Launcher зараз? [Y/n] " LAUNCH
LAUNCH=${LAUNCH:-Y}
if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
    open "$PRISM_DIR/PrismLauncher.app"
    ok "Prism запущено"
fi
