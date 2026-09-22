#!/usr/bin/env bash
# Extract QML strings (nexus for now) and compile the zh_CN catalog.
# Run from repo root: bash i18n/update-translations.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$REPO/i18n/translations/caelestia_zh_CN.ts"
QM_DIR="$REPO/i18n/translations"
SRC="${NEXUS_SRC:-$HOME/.config/quickshell/caelestia/modules/nexus}"

mkdir -p "$QM_DIR"
echo "==> lupdate (nexus)"
python3 "$REPO/i18n/extract_ts.py"

echo "==> lrelease"
/usr/bin/lrelease6 "$TS" -qm "$QM_DIR/caelestia_zh_CN.qm"

echo "==> deploy to user config (loader reads this path)"
mkdir -p "$HOME/.config/quickshell/caelestia/translations"
cp "$QM_DIR/caelestia_zh_CN.qm" "$HOME/.config/quickshell/caelestia/translations/"
echo "done: $QM_DIR/caelestia_zh_CN.qm"
