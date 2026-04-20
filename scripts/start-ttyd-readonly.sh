#!/usr/bin/env bash
# Launch a second ttyd on port 7682 in read-only mode (no --writable).
#
# Usage: sudo ./scripts/start-ttyd-readonly.sh [workspace-container-name]

set -uo pipefail
set -x

WS=${1:-coder-whatacotton-rtl-dev}
DIND=coder-dind-dind-1

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

docker exec "$DIND" docker exec -u coder "$WS" bash -c '
  pkill -x ttyd -f "port 7682" 2>/dev/null || true
  mkdir -p /home/coder/logs
  setsid nohup ttyd \
    --port 7682 \
    --interface 0.0.0.0 \
    --credential "$(cat /home/coder/.ttyd-auth)" \
    bash -l >/home/coder/logs/ttyd-ro.log 2>&1 < /dev/null &
  echo "ttyd-ro pid: $!"
  sleep 1
  echo "--- ttyd-ro.log ---"
  cat /home/coder/logs/ttyd-ro.log 2>&1 || true
  echo "--- pgrep ---"
  pgrep -af ttyd 2>&1 || echo "(no ttyd)"
  echo "--- port check ---"
  ss -tlnp 2>/dev/null | grep -E "7681|7682" || netstat -tlnp 2>/dev/null | grep -E "7681|7682" || echo "(nothing)"
'
