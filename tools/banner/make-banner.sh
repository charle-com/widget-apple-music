#!/usr/bin/env bash
# Régénère assets/banner.jpg : pochettes fictives, rendu des quatre tailles par l'app installée
# (le vrai code du widget), montage HTML, capture par Chrome sans interface.
# Prérequis : Platine installée (./build.sh --install), python3 avec Pillow, Google Chrome.
set -euo pipefail
cd "$(dirname "$0")"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
APP="/Applications/Platine.app/Contents/MacOS/Platine"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -x "${APP}" ]] || { echo "Platine n'est pas installée : ./build.sh --install" >&2; exit 1; }
[[ -x "${CHROME}" ]] || { echo "Google Chrome introuvable." >&2; exit 1; }

python3 covers.py "${WORK}/covers" "${WORK}/store/state.json"
swift derive.swift "${WORK}/covers" "${WORK}/store/art" >/dev/null
PLATINE_DIR="${WORK}/store" "${APP}" --render "${WORK}/render" >/dev/null
cp banner.html "${WORK}/banner.html"
"${CHROME}" --headless=new --disable-gpu --no-first-run --user-data-dir="${WORK}/chrome" --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1280,672 --virtual-time-budget=8000 \
  --screenshot="${WORK}/banner.png" "file://${WORK}/banner.html" >/dev/null 2>&1
python3 -c "
import sys
from PIL import Image
Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2], quality=90, optimize=True, progressive=True)
" "${WORK}/banner.png" ../../assets/banner.jpg
echo "==> assets/banner.jpg"
