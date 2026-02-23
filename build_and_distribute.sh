#!/bin/bash
# ================================================================
#  build_and_distribute.sh
#  Builds NetworkMonitor.app and packages it for sharing.
#  Run from project root. Output: NetworkMonitor-release.zip
# ================================================================

set -euo pipefail

BOLD='\033[1m'; GREEN='\033[32m'; CYAN='\033[36m'; RED='\033[31m'; R='\033[0m'
ok()  { echo -e "  ${GREEN}✔${R}  $*"; }
err() { echo -e "\n  ${RED}✖${R}  $*\n"; exit 1; }
hr()  { echo -e "${CYAN}$(printf '─%.0s' $(seq 1 56))${R}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
DIST_DIR="$SCRIPT_DIR/dist"
RELEASE_ZIP="$SCRIPT_DIR/NetworkMonitor-release.zip"

echo ""; echo -e "${BOLD}${CYAN}  📦  Network Monitor — Build & Package${R}"; hr; echo ""

[[ -f "$SCRIPT_DIR/NetworkMonitor.xcodeproj/project.pbxproj" ]] || err "Run from project root."
command -v xcodebuild &>/dev/null || err "Xcode not found."

echo -e "  ${BOLD}Building…${R}"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$SCRIPT_DIR/NetworkMonitor.xcodeproj" \
  -scheme NetworkMonitor \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | grep -E "^(error:|Build succeeded|FAILED)" | head -10 || true

APP="$BUILD_DIR/Build/Products/Release/NetworkMonitor.app"
[[ -d "$APP" ]] || err "Build failed — open in Xcode for details."
[[ -f "$APP/Contents/MacOS/NetworkMonitor" ]] || err "Binary missing after build."
ok "Build succeeded"

echo -e "\n  ${BOLD}Signing (ad-hoc)…${R}"
codesign --force --deep --sign "-" "$APP" 2>/dev/null && ok "Signed"
xattr -rc "$APP" 2>/dev/null || true

echo -e "\n  ${BOLD}Packaging…${R}"
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR/daemon"
cp -R "$APP"                             "$DIST_DIR/"
cp    "$SCRIPT_DIR/daemon/network_monitor.sh" "$DIST_DIR/daemon/"
cp    "$SCRIPT_DIR/daemon/netmon-toggle.sh"   "$DIST_DIR/daemon/"
cp    "$SCRIPT_DIR/install.sh"           "$DIST_DIR/"
cp    "$SCRIPT_DIR/README.md"            "$DIST_DIR/" 2>/dev/null || true
ok "NetworkMonitor.app  ($(du -sh "$APP" | cut -f1))"
ok "daemon scripts + install.sh"

rm -f "$RELEASE_ZIP"
cd "$SCRIPT_DIR"
zip -qr "$RELEASE_ZIP" dist/ -x "*.DS_Store" -x "__MACOSX/*"
ok "$(basename $RELEASE_ZIP)  ($(du -sh "$RELEASE_ZIP" | cut -f1))"

echo ""; hr; echo ""
echo -e "${GREEN}${BOLD}  ✅  Ready!${R}"; echo ""
echo -e "  📎  ${BOLD}${RELEASE_ZIP}${R}"
echo ""
echo -e "  Share this zip. Friends install with:"
echo -e "    1. Drag NetworkMonitor.app → /Applications"
echo -e "    2. bash install.sh"
echo ""
open "$SCRIPT_DIR" 2>/dev/null || true
