#!/bin/bash
# ================================================================
#  build_and_distribute.sh  — Network Monitor
# ================================================================

BOLD='\033[1m'; GREEN='\033[32m'; CYAN='\033[36m'
YELLOW='\033[33m'; RED='\033[31m'; R='\033[0m'
ok()   { echo -e "  ${GREEN}✔${R}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${R}  $*"; }
err()  { echo -e "\n  ${RED}✖${R}  $*\n"; exit 1; }
hr()   { echo -e "${CYAN}$(printf '─%.0s' $(seq 1 56))${R}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
DIST_DIR="$SCRIPT_DIR/dist"
RELEASE_ZIP="$SCRIPT_DIR/NetworkMonitor-release.zip"
LOG="$SCRIPT_DIR/.build_log.txt"

echo ""
echo -e "${BOLD}${CYAN}  📦  Network Monitor — Build & Package${R}"
hr; echo ""

# ── Sanity checks ─────────────────────────────────────────────────
[[ -f "$SCRIPT_DIR/NetworkMonitor.xcodeproj/project.pbxproj" ]] \
  || err "Run from project root (where NetworkMonitor.xcodeproj is)."

command -v xcodebuild &>/dev/null \
  || err "Xcode command line tools not found. Run: xcode-select --install"

echo -e "  Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo -e "  SDK:   $(xcodebuild -showsdks 2>/dev/null | grep 'macosx' | tail -1 | sed 's/^[[:space:]]*//')"
echo ""

# ── Build ─────────────────────────────────────────────────────────
echo -e "  ${BOLD}Building (Release)…${R}"
rm -rf "$BUILD_DIR"

# Run xcodebuild and tee output so errors print live AND go to log
xcodebuild \
  -project "$SCRIPT_DIR/NetworkMonitor.xcodeproj" \
  -scheme NetworkMonitor \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | tee "$LOG" | grep -E "(error:|warning:|Build succeeded|BUILD FAILED|SwiftCompile|CompileSwift)" | grep -v "warning:" | head -40

BUILD_STATUS="${PIPESTATUS[0]}"

echo ""

# ── Check result ──────────────────────────────────────────────────
if grep -q "BUILD FAILED" "$LOG" 2>/dev/null; then
  echo -e "  ${RED}BUILD FAILED. Errors:${R}"
  echo ""
  grep "error:" "$LOG" | sed 's|.*/NetworkMonitor/||' | head -30
  echo ""
  echo -e "  Full log saved to: ${YELLOW}$LOG${R}"
  echo -e "  Or open in Xcode: ${CYAN}open NetworkMonitor.xcodeproj${R}"
  exit 1
fi

# Find the .app — search broadly since path varies by Xcode version
APP=$(find "$BUILD_DIR" -name "NetworkMonitor.app" -not -path "*/Index.noindex/*" -not -path "*/.build/SourcePackages/*" 2>/dev/null | head -1)

if [[ -z "$APP" ]]; then
  echo -e "  ${RED}Build appeared to succeed but .app not found. Searching:${R}"
  find "$BUILD_DIR" -name "*.app" 2>/dev/null | head -10
  echo ""
  echo -e "  Last lines of build log:"
  tail -20 "$LOG"
  err "Could not locate NetworkMonitor.app"
fi

BIN="$APP/Contents/MacOS/NetworkMonitor"
if [[ ! -f "$BIN" ]]; then
  echo -e "  ${RED}App bundle found but binary missing:${R} $APP"
  echo "  Contents of MacOS/:"
  ls -la "$APP/Contents/MacOS/" 2>/dev/null || echo "  (directory empty or missing)"
  echo ""
  echo "  Last build errors:"
  grep "error:" "$LOG" | tail -20
  err "Binary missing after build."
fi

ok "Built: $(du -sh "$APP" | cut -f1)  →  $APP"

# ── Sign ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Signing…${R}"
codesign --force --deep --sign "-" "$APP" 2>/dev/null && ok "Signed (ad-hoc)" || warn "Signing skipped"
xattr -rc "$APP" 2>/dev/null || true
ok "Quarantine stripped"

# ── Package ───────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Packaging…${R}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/daemon"

cp -R "$APP" "$DIST_DIR/"
[[ -f "$SCRIPT_DIR/daemon/network_monitor.sh" ]] && cp "$SCRIPT_DIR/daemon/network_monitor.sh" "$DIST_DIR/daemon/" || warn "daemon/network_monitor.sh not found"
[[ -f "$SCRIPT_DIR/daemon/netmon-toggle.sh"   ]] && cp "$SCRIPT_DIR/daemon/netmon-toggle.sh"   "$DIST_DIR/daemon/" || true
[[ -f "$SCRIPT_DIR/install.sh" ]]                && cp "$SCRIPT_DIR/install.sh"   "$DIST_DIR/"  || warn "install.sh not found"
[[ -f "$SCRIPT_DIR/README.md"  ]]                && cp "$SCRIPT_DIR/README.md"    "$DIST_DIR/"  || true
chmod +x "$DIST_DIR/install.sh" "$DIST_DIR/daemon/"*.sh 2>/dev/null || true

rm -f "$RELEASE_ZIP"
cd "$SCRIPT_DIR"
zip -qr "$RELEASE_ZIP" dist/ -x "*.DS_Store" -x "__MACOSX/*"

ok "Created: $(du -sh "$RELEASE_ZIP" | cut -f1)  →  $RELEASE_ZIP"

# ── Done ──────────────────────────────────────────────────────────
echo ""; hr; echo ""
echo -e "${GREEN}${BOLD}  ✅  Done! Share this file:${R}"
echo ""
echo -e "  📎  ${BOLD}$RELEASE_ZIP${R}"
echo ""
echo -e "  Friends install with:"
echo -e "    1. Drag NetworkMonitor.app → /Applications"
echo -e "    2. bash install.sh"
echo ""
open "$SCRIPT_DIR" 2>/dev/null || true
