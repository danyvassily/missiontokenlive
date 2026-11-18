#!/bin/bash
# Démarre MissionTokenLive dès que le gateway Hermes est en écoute.
# Appelé par launchd au login. `open -g` est idempotent : si l'app tourne déjà,
# macOS la réutilise sans voler le focus — pas de test « déjà lancée » à maintenir.
APP="/Applications/MissionTokenLive.app"
LOG="$HOME/.hermes/logs/missiontoken-autostart.log"
mkdir -p "$(dirname "$LOG")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -d "$APP" ] || { log "app absente"; exit 0; }

gateway_up() {
  local pidfile="$HOME/.hermes/gateway.pid" pid
  if [ -f "$pidfile" ]; then
    pid=$(sed -nE 's/.*"pid": *([0-9]+).*/\1/p' "$pidfile" | head -1)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then return 0; fi
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8642 -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi
  return 1
}

for _ in $(seq 1 45); do
  if gateway_up; then
    open -g "$APP" && log "lancement demandé (gateway prêt)"
    exit 0
  fi
  sleep 2
done
log "gateway absent après 90 s, abandon"
exit 0
