#!/usr/bin/env bash
# Diagnose whether ttyd is running and listening inside the workspace.
#
# Usage: sudo ./scripts/check-ttyd.sh [workspace-container-name]
# Default name: coder-whatacotton-rtl-dev

set -uo pipefail

WS=${1:-coder-whatacotton-rtl-dev}
DIND=coder-dind-dind-1

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

section() {
  printf '\n===== %s =====\n' "$1"
}

section "ttyd process"
docker exec "$DIND" docker exec "$WS" pgrep -af ttyd 2>&1 || echo "(no ttyd process)"

section "/usr/local/bin/ttyd binary"
docker exec "$DIND" docker exec "$WS" ls -la /usr/local/bin/ttyd 2>&1

section "ttyd.log tail"
docker exec "$DIND" docker exec "$WS" tail -40 /home/coder/logs/ttyd.log 2>&1

section "listening sockets (7681)"
docker exec "$DIND" docker exec "$WS" sh -c 'ss -tlnp 2>/dev/null | grep 7681 || netstat -tlnp 2>/dev/null | grep 7681 || echo "(nothing on 7681)"'

section "basic auth credential file"
docker exec "$DIND" docker exec "$WS" ls -la /home/coder/.ttyd-auth 2>&1
docker exec "$DIND" docker exec "$WS" cat /home/coder/.ttyd-auth 2>&1

section "startup_script status"
docker logs "$DIND" 2>&1 | tail -5 >/dev/null || true
docker exec "$DIND" docker logs "$WS" 2>&1 | grep -iE 'script failed|exit_code|startup-script' | tail -5

section "startup_script tail (plain text)"
docker exec "$DIND" docker exec "$WS" sh -c 'strings /tmp/coder-startup-script.log | tail -20' 2>&1
