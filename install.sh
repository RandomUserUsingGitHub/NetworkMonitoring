#!/bin/bash
# ================================================================
#  install.sh — Network Monitor installer
#  Installs the background daemon. Settings are configured in-app.
#
#  Usage:
#    bash install.sh             ← install
#    bash install.sh --uninstall ← remove everything
# ================================================================

set -euo pipefail

BOLD='\033[1m'; GREEN='\033[32m'; CYAN='\033[36m'
YELLOW='\033[33m'; RED='\033[31m'; R='\033[0m'
ok()   { echo -e "  ${GREEN}✔${R}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${R}  $*"; }
err()  { echo -e "\n  ${RED}✖${R}  $*\n"; exit 1; }
hr()   { echo -e "${CYAN}$(printf '─%.0s' $(seq 1 54))${R}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/network-monitor"
AGENTS_DIR="$HOME/Library/LaunchAgents"
DAEMON_PLIST="$AGENTS_DIR/com.user.network-monitor.plist"
APP_PATH="/Applications/NetworkMonitor.app"
APP_BIN="$APP_PATH/Contents/MacOS/NetworkMonitor"

# ── UNINSTALL ────────────────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
  echo ""; echo -e "${BOLD}${RED}  🗑  Network Monitor — Uninstall${R}"; hr; echo ""
  osascript -e 'tell application "NetworkMonitor" to quit' 2>/dev/null || true
  launchctl unload "$DAEMON_PLIST" 2>/dev/null && ok "Daemon stopped" || true
  rm -f "$DAEMON_PLIST"                   && ok "Removed LaunchAgent"
  rm -f "$INSTALL_DIR/network_monitor.sh" && ok "Removed daemon script"
  rm -f "$INSTALL_DIR/netmon-toggle.sh"   && ok "Removed toggle script"
  read -rp "  Remove config and log? [y/N]: " yn
  if [[ "$(echo "${yn:-n}" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    rm -rf "$CFG_DIR" && ok "Removed config"
    rm -f "$HOME/.network_monitor.log" && ok "Removed log"
  fi
  echo ""; echo -e "${GREEN}  ✅  Uninstalled.${R}"; echo ""; exit 0
fi

# ── INSTALL ──────────────────────────────────────────────────────
clear; echo ""
echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${R}"
echo -e "${BOLD}${CYAN}  ║    🌐  Network Monitor  Installer        ║${R}"
echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${R}"
echo ""

# macOS version check
macos_major=$(sw_vers -productVersion | cut -d. -f1)
(( macos_major >= 13 )) || err "macOS 13+ required. You have $(sw_vers -productVersion)"
ok "macOS $(sw_vers -productVersion)"

# App check
if [[ ! -d "$APP_PATH" ]]; then
  echo ""
  echo -e "  ${RED}✖  NetworkMonitor.app not in /Applications${R}"
  echo -e "  Drag it there first, then re-run this script."
  open "$SCRIPT_DIR" 2>/dev/null || true; exit 1
fi
if [[ ! -f "$APP_BIN" ]]; then
  echo ""
  echo -e "  ${RED}✖  App binary missing — the .app was not built before packaging.${R}"
  echo -e "  Ask the developer to run:  bash build_and_distribute.sh"
  exit 1
fi
ok "NetworkMonitor.app is valid"

hr; echo ""
echo -e "  ${BOLD}Settings are configured inside the app.${R}"
echo -e "  The daemon will start with sensible defaults."
echo -e "  Change anything via the ⚙️ gear icon after launch."
echo ""; hr; echo ""

# ── Install files ────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR" "$CFG_DIR" "$AGENTS_DIR"

# Write a minimal default config (app will overwrite on first run)
if [[ ! -f "$CFG_DIR/settings.json" ]]; then
  cat > "$CFG_DIR/settings.json" <<'JSON'
{
  "ping": { "host": "8.8.8.8", "interval_seconds": 2, "fail_threshold": 3,
            "timeout_seconds": 2, "packet_size": 56, "history_size": 60 },
  "ip_check": { "interval_seconds": 10 },
  "notifications": { "sound": "Basso", "enabled": true, "censor_on_change": false },
  "ui": { "theme": "green", "ping_graph_width": 60 },
  "log": { "tail_lines": 7 }
}
JSON
  ok "Default config written"
fi

DAEMON_SRC="$SCRIPT_DIR/daemon/network_monitor.sh"
[[ -f "$DAEMON_SRC" ]] || err "daemon/network_monitor.sh not found. Re-download the package."

cp "$DAEMON_SRC" "$INSTALL_DIR/network_monitor.sh"
chmod +x "$INSTALL_DIR/network_monitor.sh"
ok "Daemon script installed"

if [[ -f "$SCRIPT_DIR/daemon/netmon-toggle.sh" ]]; then
  cp "$SCRIPT_DIR/daemon/netmon-toggle.sh" "$INSTALL_DIR/netmon-toggle.sh"
  chmod +x "$INSTALL_DIR/netmon-toggle.sh"
  ok "Toggle script installed"
fi

cat > "$DAEMON_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>com.user.network-monitor</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${INSTALL_DIR}/network_monitor.sh</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>/tmp/netmon_stdout.log</string>
  <key>StandardErrorPath</key> <string>/tmp/netmon_stderr.log</string>
</dict>
</plist>
PLIST

launchctl unload "$DAEMON_PLIST" 2>/dev/null || true
launchctl load   "$DAEMON_PLIST"
ok "Daemon installed and started"

# ── Open app ─────────────────────────────────────────────────────
hr; echo ""
read -rp "  Open NetworkMonitor now? [Y/n]: " open_yn
if [[ "$(echo "${open_yn:-y}" | tr '[:upper:]' '[:lower:]')" != "n" ]]; then
  if ! open "$APP_PATH" 2>/dev/null; then
    warn "Removing quarantine and retrying…"
    xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    sleep 0.3
    open "$APP_PATH" 2>/dev/null && ok "App launched" || {
      echo -e "  ${YELLOW}Please open NetworkMonitor manually from /Applications${R}"
      echo -e "  If blocked: right-click → Open → Open Anyway"
    }
  else
    ok "App launched"
  fi
fi

echo ""; hr; echo ""
echo -e "${GREEN}${BOLD}  ✅  Done!${R}"; echo ""
echo -e "  Toggle daemon:  ${CYAN}bash ~/.local/bin/netmon-toggle.sh${R}"
echo -e "  View log:       ${CYAN}tail -f ~/.network_monitor.log${R}"
echo -e "  Uninstall:      ${CYAN}bash install.sh --uninstall${R}"
echo -e "  Settings:       ${CYAN}⚙️ gear icon inside the app${R}"
echo ""
