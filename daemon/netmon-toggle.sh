#!/bin/bash
# ================================================================
#  netmon-toggle.sh — global start/stop toggle
#
#  Assign to a keyboard shortcut via:
#   • Automator → Quick Action → Run Shell Script
#   • Raycast   → Script Command
#   • BetterTouchTool → Shell Script trigger
# ================================================================

DAEMON_PLIST="$HOME/Library/LaunchAgents/com.user.network-monitor.plist"
UI_BIN="$HOME/.local/bin/network_monitor_ui.sh"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\" sound name \"Purr\""
}

daemon_running() {
  launchctl list 2>/dev/null | awk '{print $3}' | grep -qx "com.user.network-monitor"
}

ui_open() {
  osascript -e \
    'tell application "Terminal" to get every window whose custom title is "🌐 Network Monitor"' \
    2>/dev/null | grep -q "window"
}

if daemon_running; then
  # ── STOP ────────────────────────────────────────────────────────
  launchctl unload "$DAEMON_PLIST" 2>/dev/null || true

  # Close the UI window gracefully if open
  osascript <<'AS' 2>/dev/null || true
tell application "Terminal"
  repeat with w in windows
    if custom title of w is "🌐 Network Monitor" then
      close w
      exit repeat
    end if
  end repeat
end tell
AS

  notify "🛑 Network Monitor" "Daemon stopped. Dashboard closed."
  echo "Stopped."
else
  # ── START ────────────────────────────────────────────────────────
  launchctl load "$DAEMON_PLIST" 2>/dev/null || true
  sleep 0.5
  bash "$UI_BIN"
  notify "▶ Network Monitor" "Daemon started. Dashboard open."
  echo "Started."
fi
