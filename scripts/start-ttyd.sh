#!/usr/bin/env bash
# Start ttyd inside the workspace container manually (useful before the
# new template is applied via web-console update).
#
# Usage: sudo ./scripts/start-ttyd.sh [workspace-container-name]

set -uo pipefail
set -x

WS=${1:-coder-whatacotton-rtl-dev}
DIND=coder-dind-dind-1

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

# Use setsid + disown so ttyd survives after this docker exec returns.
docker exec "$DIND" docker exec -u coder "$WS" bash -c '
  pkill -x ttyd 2>/dev/null || true
  mkdir -p /home/coder/logs
  setsid nohup ttyd \
    --port 7681 \
    --interface 0.0.0.0 \
    --credential "$(cat /home/coder/.ttyd-auth)" \
    --writable \
    bash -l >/home/coder/logs/ttyd.log 2>&1 < /dev/null &
  echo "ttyd pid: $!"
  sleep 1
  echo "--- ttyd.log ---"
  cat /home/coder/logs/ttyd.log 2>&1 || true
  echo "--- pgrep ---"
  pgrep -af ttyd 2>&1 || echo "(no ttyd process)"
  echo "--- port check ---"
  ss -tlnp 2>/dev/null | grep 7681 || netstat -tlnp 2>/dev/null | grep 7681 || echo "(nothing on 7681)"
  echo "--- credentials ---"
  cat /home/coder/.ttyd-auth
'
