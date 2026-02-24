#!/bin/bash
# ================================================================
#  network_monitor.sh — background daemon
#  Config:  ~/.config/network-monitor/settings.json
#  State:   /tmp/.netmon_ping_history
#           /tmp/.netmon_ip_state
#           /tmp/.netmon_status
# ================================================================

CFG="$HOME/.config/network-monitor/settings.json"

jget() {
  awk "/\"$1\"/{f=1} f && /\"$2\"/{
    sub(/^[^:]*: *\"?/, \"\")
    sub(/\"? *,? *$/, \"\")
    print; exit
  }" "$CFG" 2>/dev/null
}

reload_config() {
  PING_HOST=$(jget ping host);                    PING_HOST=${PING_HOST:-8.8.8.8}
  PING_INTERVAL=$(jget ping interval_seconds);    PING_INTERVAL=${PING_INTERVAL:-2}
  FAIL_THRESHOLD=$(jget ping fail_threshold);     FAIL_THRESHOLD=${FAIL_THRESHOLD:-3}
  PING_TIMEOUT=$(jget ping timeout_seconds);      PING_TIMEOUT=${PING_TIMEOUT:-2}
  PACKET_SIZE=$(jget ping packet_size);           PACKET_SIZE=${PACKET_SIZE:-56}
  HISTORY_SIZE=$(jget ping history_size);         HISTORY_SIZE=${HISTORY_SIZE:-60}
  IP_INTERVAL=$(jget ip_check interval_seconds);  IP_INTERVAL=${IP_INTERVAL:-10}
  NOTIF_SOUND=$(jget notifications sound);        NOTIF_SOUND=${NOTIF_SOUND:-Basso}
  NOTIF_ENABLED=$(jget notifications enabled);    NOTIF_ENABLED=${NOTIF_ENABLED:-true}
  CENSOR_IP=$(jget notifications censor_on_change); CENSOR_IP=${CENSOR_IP:-false}
  LOG_PATH=$(jget log path | sed "s|~|$HOME|");   LOG_PATH=${LOG_PATH:-$HOME/.network_monitor.log}

  # Convert timeout to milliseconds for ping -W (macOS uses ms)
  PING_TIMEOUT_MS=$(awk -v t="$PING_TIMEOUT" 'BEGIN{printf "%d", t*1000}')
  # macOS ping -W minimum is 1ms
  (( PING_TIMEOUT_MS < 1 )) && PING_TIMEOUT_MS=1
}

reload_config

HIST="/tmp/.netmon_ping_history"
IP_STATE="/tmp/.netmon_ip_state"
STATUS="/tmp/.netmon_status"

# ── helpers ─────────────────────────────────────────────────────

notify() {
  # Disabled in favor of native Swift UNUserNotificationCenter
  return
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_PATH"; }

get_public_ip() {
  curl -sf --max-time 5 "https://api.ipify.org"          2>/dev/null && return
  curl -sf --max-time 5 "https://ifconfig.me/ip"         2>/dev/null && return
  curl -sf --max-time 5 "https://checkip.amazonaws.com"  2>/dev/null && return
  echo ""
}

get_geo() {
  local ip="$1" resp country city
  [[ -z "$ip" ]] && echo "Unknown|Unknown" && return
  resp=$(curl -sf --max-time 5 "http://ip-api.com/json/${ip}?fields=status,country,city" 2>/dev/null)
  if [[ "$resp" == *'"success"'* ]]; then
    country=$(echo "$resp" | sed 's/.*"country":"\([^"]*\)".*/\1/')
    city=$(   echo "$resp" | sed 's/.*"city":"\([^"]*\)".*/\1/')
    echo "${country}|${city}"; return
  fi
  resp=$(curl -sf --max-time 5 "https://ipinfo.io/${ip}/json" 2>/dev/null)
  if [[ -n "$resp" ]]; then
    country=$(echo "$resp" | sed 's/.*"country":[ ]*"\([^"]*\)".*/\1/')
    city=$(   echo "$resp" | sed 's/.*"city":[ ]*"\([^"]*\)".*/\1/')
    echo "${country}|${city}"; return
  fi
  echo "Unknown|Unknown"
}

censor_ip() {
  local ip="$1"
  # Show first octet, censor the rest: 1.2.3.4 → 1.*.*.*
  echo "$ip" | sed 's/\.[0-9]*\.[0-9]*\.[0-9]*$/.*.*.*/'
}

append_ping() {
  echo "$1" >> "$HIST"
  local n; n=$(wc -l < "$HIST")
  if (( n > HISTORY_SIZE )); then
    tail -n "$HISTORY_SIZE" "$HIST" > "${HIST}.tmp" && mv "${HIST}.tmp" "$HIST"
  fi
}

# ── init ────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_PATH")"
: > "$HIST"
echo "fetching||" > "$IP_STATE"
echo "STARTING"   > "$STATUS"

fail_count=0; outage_active=false
last_ip=""; last_ip_check=0
cfg_mtime=0

log "=== Network Monitor started (host:${PING_HOST} interval:${PING_INTERVAL}s timeout:${PING_TIMEOUT}s pktsize:${PACKET_SIZE}b threshold:${FAIL_THRESHOLD}) ==="

# ── main loop ───────────────────────────────────────────────────
while true; do
  now=$(date +%s)

  # Reload config if settings.json was modified
  current_mtime=$(stat -f %m "$CFG" 2>/dev/null || echo 0)
  if (( current_mtime != cfg_mtime )); then
    reload_config
    cfg_mtime=$current_mtime
    log "Config reloaded (threshold:${FAIL_THRESHOLD} timeout:${PING_TIMEOUT}s pktsize:${PACKET_SIZE}b)"
  fi

  # Ping — macOS: -c count -W timeout_ms -s packet_size
  ping_out=$(ping -c 1 -W "$PING_TIMEOUT_MS" -s "$PACKET_SIZE" "$PING_HOST" 2>/dev/null)

  if echo "$ping_out" | grep -qE 'round-trip|rtt'; then
    ms=$(echo "$ping_out" | grep -E 'round-trip|rtt' | awk -F'/' '{printf "%.1f",$5}')
    [[ -z "$ms" ]] && ms="1.0"
    append_ping "$ms"
    echo "ONLINE" > "$STATUS"
    if $outage_active; then
      log "Connection restored after $fail_count failures."
      notify "🟢 Internet Restored" "Connection to $PING_HOST is back."
      outage_active=false
    fi
    fail_count=0
  else
    append_ping "T"
    (( fail_count++ ))
    log "Ping failed ($fail_count/$FAIL_THRESHOLD)"
    # Only trigger OUTAGE when threshold reached AND not already in outage
    if (( fail_count >= FAIL_THRESHOLD )) && ! $outage_active; then
      log "OUTAGE detected after $fail_count consecutive failures."
      notify "🔴 Internet Outage" "No response from $PING_HOST after $fail_count attempts."
      outage_active=true
      echo "OFFLINE" > "$STATUS"
    fi
  fi

  # IP check
  if (( now - last_ip_check >= IP_INTERVAL )); then
    last_ip_check=$now
    current_ip=$(get_public_ip)
    if [[ -n "$current_ip" && "$current_ip" != "$last_ip" ]]; then
      geo=$(get_geo "$current_ip")
      country="${geo%%|*}"; city="${geo##*|}"

      # Decide what to show in notification/log
      if [[ "$CENSOR_IP" == "true" ]]; then
        display_ip=$(censor_ip "$current_ip")
      else
        display_ip="$current_ip"
      fi

      if [[ -n "$last_ip" ]]; then
        if [[ "$CENSOR_IP" == "true" ]]; then
          display_old=$(censor_ip "$last_ip")
        else
          display_old="$last_ip"
        fi
        log "IP changed: $display_old → $display_ip ($city, $country)"
        notify "🌐 Public IP Changed" "New IP: $display_ip | $city, $country"
      else
        log "Initial IP: $display_ip ($city, $country)"
      fi

      last_ip="$current_ip"
      # Always store real IP in state file (app controls display)
      echo "${current_ip}|${country}|${city}" > "$IP_STATE"
    fi
  fi

  sleep "$PING_INTERVAL"
done
