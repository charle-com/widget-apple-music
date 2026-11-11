#!/usr/bin/env bash
# Construit Platine.app (agent + adaptateur MediaRemote + widget embarqué) dans ./build/, signe et vérifie.
#
#   ./build.sh              construit et vérifie
#   ./build.sh --install    construit puis installe dans /Applications (remplace l'ancienne version) et lance
#   ./build.sh --debug      build debug (plus rapide)
#   ./build.sh --test       lance les tests du cœur avant le build
#   ./build.sh --uninstall  quitte l'app, la retire de /Applications et de l'ouverture de session
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Platine"

# Réglages facultatifs : une variable d'environnement, ou une ligne CLÉ=valeur dans build.local.conf
# (fichier hors git, propre à chaque machine). La variable d'environnement passe avant le fichier.
#   BUNDLE_ID         identifiant de l'app ; le widget prend le même, suivi de .widget
#   SIGNING_IDENTITY  nom d'une identité de signature du trousseau ; sans elle, signature ad hoc
setting() {
  local value="${!1:-}"
  if [[ -z "${value}" && -f build.local.conf ]]; then
    value="$(grep -m1 -E "^$1=" build.local.conf | cut -d= -f2- || true)"
  fi
  printf '%s' "${value:-$2}"
}
BUNDLE_ID="$(setting BUNDLE_ID "io.github.charle-com.platine")"
WIDGET_ID="${BUNDLE_ID}.widget"
SIGNING_IDENTITY="$(setting SIGNING_IDENTITY "-")"
BUILD_DIR="./build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"
APPEX_DIR="${APP_DIR}/Contents/PlugIns/PlatineWidget.appex"
INSTALLED="/Applications/${APP_NAME}.app"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
CONFIG="release"
SCRATCH="${SCRATCH:-.build}"
DO_INSTALL=0
DO_TEST=0
DO_UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --install) DO_INSTALL=1 ;;
    --debug) CONFIG="debug" ;;
    --test) DO_TEST=1 ;;
    --uninstall) DO_UNINSTALL=1 ;;
  esac
done

fail() { echo ""; echo "❌ $1" >&2; exit 1; }

quit_app() {
  pkill -x "${APP_NAME}" 2>/dev/null || true
  # L'adaptateur s'arrête seul quand l'app disparaît, on n'attend pas son prochain réveil.
  pkill -f "libPlatineAdapter.dylib" 2>/dev/null || true
  sleep 1
}

if [[ "${DO_UNINSTALL}" == "1" ]]; then
  quit_app
  osascript -e 'tell application "System Events" to delete (every login item whose name is "Platine")' >/dev/null 2>&1 || true
  pluginkit -r "${INSTALLED}/Contents/PlugIns/PlatineWidget.appex" 2>/dev/null || true
  "${LSREG}" -u "${INSTALLED}" >/dev/null 2>&1 || true
  rm -rf "${INSTALLED}"
  echo "==> Désinstallé. Restent, à supprimer à la main si tu veux tout effacer :"
  echo "    ~/Library/Application Support/Platine  (état et pochettes)"
  echo "    ~/Library/Logs/Platine"
  exit 0
fi

EXTRA_FLAGS=()
# Xcode si sa licence est acceptée, sinon les Command Line Tools (SDK et WidgetKit inclus, ça suffit).
if [[ -d "/Applications/Xcode.app/Contents/Developer" ]] && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  SWIFT_BIN="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
elif [[ -x "/Library/Developer/CommandLineTools/usr/bin/swift" ]]; then
  export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
  SWIFT_BIN="${DEVELOPER_DIR}/usr/bin/swift"
  # Les macros SwiftUI ne sont livrées qu'avec Xcode.
  XC_PLUGINS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
  if [[ -d "${XC_PLUGINS}" ]]; then
    EXTRA_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "${XC_PLUGINS}")
  fi
else
  fail "Ni Xcode (licence acceptée) ni Command Line Tools."
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
echo "==> ${APP_NAME} ${VERSION} (${CONFIG})"

if [[ "${DO_TEST}" == "1" ]]; then
  echo "==> Tests…"
  # Sans EXTRA_FLAGS : un -plugin-path explicite masque les macros de Swift Testing.
  "${SWIFT_BIN}" test --scratch-path "${SCRATCH}-tests" 2>&1 | grep -E "✘|Test run|error:" | tail -20
fi

echo "==> Compilation Swift…"
"${SWIFT_BIN}" build --scratch-path "${SCRATCH}" -c "${CONFIG}" --arch arm64 --product Platine ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} 2>&1 | grep -E "error|Build complete" || true
"${SWIFT_BIN}" build --scratch-path "${SCRATCH}" -c "${CONFIG}" --arch arm64 --product PlatineWidget ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} 2>&1 | grep -E "error|Build complete" || true
BIN_DIR="$("${SWIFT_BIN}" build --scratch-path "${SCRATCH}" -c "${CONFIG}" --arch arm64 ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} --show-bin-path)"
[[ -x "${BIN_DIR}/Platine" ]] || fail "Binaire introuvable : ${BIN_DIR}/Platine"
[[ -x "${BIN_DIR}/PlatineWidget" ]] || fail "Binaire du widget introuvable : ${BIN_DIR}/PlatineWidget"

echo "==> Assemblage de ${APP_NAME}.app…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}" "${APPEX_DIR}/Contents/MacOS"
cp "${BIN_DIR}/Platine" "${MACOS_DIR}/Platine"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${BIN_DIR}/PlatineWidget" "${APPEX_DIR}/Contents/MacOS/PlatineWidget"
cp "Resources/WidgetInfo.plist" "${APPEX_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  -c "Set :CFBundleURLTypes:0:CFBundleURLName ${BUNDLE_ID}" "${APP_DIR}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${WIDGET_ID}" "${APPEX_DIR}/Contents/Info.plist"
echo 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> Compilation de l'adaptateur MediaRemote…"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=15.0 -framework Foundation \
  Adapter/adapter.m -o "${RES_DIR}/libPlatineAdapter.dylib" || fail "Compilation de l'adaptateur."

if [[ ! -f "Resources/AppIcon.icns" ]]; then
  echo "==> Génération de l'icône…"
  "${SWIFT_BIN}" make-icon.swift Resources/AppIcon.icns || echo "    (icône non générée, l'app garde l'icône par défaut)"
fi
[[ -f "Resources/AppIcon.icns" ]] && cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"

# Signature de l'intérieur vers l'extérieur : adaptateur, widget, puis app. L'app et le widget doivent porter
# la même identité. Par défaut la signature est ad hoc, sans rien à préparer. Une identité du trousseau
# (SIGNING_IDENTITY) garde la même signature d'un build à l'autre.
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  echo "==> Signature ad hoc…"
  SIGN=("-")
  TS=()
else
  security find-identity -v -p codesigning | grep -q "${SIGNING_IDENTITY}" \
    || fail "Identité de signature '${SIGNING_IDENTITY}' absente du trousseau."
  echo "==> Signature avec '${SIGNING_IDENTITY}'…"
  SIGN=("${SIGNING_IDENTITY}")
  TS=(--timestamp=none)
fi
codesign --force --sign "${SIGN[@]}" ${TS[@]+"${TS[@]}"} "${RES_DIR}/libPlatineAdapter.dylib"
codesign --force --sign "${SIGN[@]}" ${TS[@]+"${TS[@]}"} --identifier "${WIDGET_ID}" --entitlements PlatineWidget.entitlements "${APPEX_DIR}"
codesign --force --sign "${SIGN[@]}" ${TS[@]+"${TS[@]}"} --identifier "${BUNDLE_ID}" --entitlements Platine.entitlements "${APP_DIR}"
codesign --verify --strict --verbose=1 "${APP_DIR}" 2>&1 | sed 's/^/    /' || fail "Signature invalide."
codesign --verify --strict --verbose=1 "${APPEX_DIR}" 2>&1 | sed 's/^/    /' || fail "Signature du widget invalide."

echo "==> OK : ${APP_DIR}"
# La copie de build ne doit jamais répondre à platine:// ni figurer parmi les candidats LaunchServices.
"${LSREG}" -u "$(cd "${APP_DIR}" && pwd)" >/dev/null 2>&1 || true

if [[ "${DO_INSTALL}" == "1" ]]; then
  echo "==> Installation dans /Applications…"
  quit_app
  rm -rf "${INSTALLED}"
  cp -R "${APP_DIR}" "${INSTALLED}"
  "${LSREG}" -u "$(cd "${APP_DIR}" && pwd)" >/dev/null 2>&1 || true
  # Enregistre l'app et son widget auprès de LaunchServices et de PlugInKit.
  "${LSREG}" -f -R "${INSTALLED}" >/dev/null 2>&1 || true
  pluginkit -a "${INSTALLED}/Contents/PlugIns/PlatineWidget.appex" 2>/dev/null || true
  # chronod relance l'extension avec le nouveau binaire.
  pkill -f "PlatineWidget.appex" 2>/dev/null || true
  echo "==> Installé : ${INSTALLED}"
  open -a "${INSTALLED}"
fi
