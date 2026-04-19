#!/usr/bin/env bash
# publish.sh — ставить тег і пушить. GitHub Actions сам збирає .exe і робить реліз.
#
# Використання:
#   ./publish.sh            # автогенерована версія yyyy.mm.dd-N
#   ./publish.sh v1.0.0     # своя версія
#
# Потрібно: git з доступом до origin.

set -euo pipefail

cd "$(dirname "$0")"

[ -d .git ] || { echo "✗ Не git-репо"; exit 1; }

if [ "${1:-}" != "" ]; then
    VERSION="${1#v}"
else
    DATE=$(date +%Y.%m.%d)
    N=$(git tag -l "v${DATE}-*" | wc -l)
    VERSION="${DATE}-$((N + 1))"
fi
TAG="v${VERSION}"

echo "→ Версія: $TAG"

if [ -n "$(git status --porcelain)" ]; then
    echo "→ Коміт поточних змін..."
    git add -A
    git commit -m "release ${TAG}"
    git push
fi

echo "→ Тег + push → workflow збере і зарелізить..."
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "✓ Тег запушено. Спостерігай:"
echo "  https://github.com/asemelinsky/kodomandry-installer/actions"
echo ""
echo "  Коли workflow завершиться, реліз буде тут:"
echo "  https://github.com/asemelinsky/kodomandry-installer/releases/tag/${TAG}"
echo ""
echo "  Стабільні посилання (не ламаються):"
echo "  https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/KodomandryInstaller.exe"
echo "  https://github.com/asemelinsky/kodomandry-installer/releases/latest/download/install.command"
