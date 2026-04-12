#!/usr/bin/env bash
# publish.sh — пакує інсталятор і створює GitHub Release.
#
# Використання:
#   ./publish.sh            # автогенерована версія yyyy.mm.dd-N
#   ./publish.sh v1.0.0     # своя версія
#
# Залежності: gh (GitHub CLI, автентифікований), zip
#
# URL у content/download/windows.md статичні (releases/latest/download/...),
# тож KB не треба перебудовувати після кожного релізу — лише якщо змінилися тексти.

set -euo pipefail

cd "$(dirname "$0")"

# --- Перевірки ---
command -v gh >/dev/null || { echo "✗ gh CLI не знайдено"; exit 1; }
command -v zip >/dev/null || { echo "✗ zip не знайдено"; exit 1; }
[ -d .git ] || { echo "✗ Не git-репо. Зроби: git init && gh repo create asemelinsky/kodomandry-installer --public --source=. --push"; exit 1; }

# --- Версія ---
if [ "${1:-}" != "" ]; then
    VERSION="$1"
else
    DATE=$(date +%Y.%m.%d)
    N=$(git tag -l "${DATE}-*" | wc -l)
    VERSION="${DATE}-$((N + 1))"
fi

TAG="v${VERSION}"
OUT_DIR="dist"
WIN_ZIP="${OUT_DIR}/kodomandry-installer-windows.zip"

echo "→ Версія: $TAG"

# --- Пакування ---
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "→ Пакування Windows..."
(cd windows && zip -r "../${WIN_ZIP}" install.cmd install.ps1 README.md)
echo "  ✓ ${WIN_ZIP} ($(du -h "$WIN_ZIP" | cut -f1))"

# TODO: macOS коли буде готово
# (cd macos && zip -r "../${OUT_DIR}/kodomandry-installer-macos.zip" install.sh README.md)

# --- Коміт статусу (якщо є зміни) ---
if [ -n "$(git status --porcelain)" ]; then
    echo "→ Коміт поточних змін..."
    git add -A
    git commit -m "release ${TAG}"
    git push
fi

# --- Тег + реліз ---
echo "→ Створення GitHub Release ${TAG}..."
git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" \
    --title "Kodomandry Installer ${VERSION}" \
    --notes "Windows installer. Подвійний клік на \`install.cmd\` у розпакованій папці.

Див. [README](https://github.com/asemelinsky/kodomandry-installer#readme) для деталей." \
    "$WIN_ZIP"

echo ""
echo "✓ Готово: https://github.com/asemelinsky/kodomandry-installer/releases/tag/${TAG}"
echo ""
echo "  Стабільне посилання для KB (не змінюється):"
echo "  https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/kodomandry-installer-windows.zip"
