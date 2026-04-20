#!/usr/bin/env bash
# Inspect the state of a running Coder workspace started inside the
# system-docker dind container. Shows startup_script progress, log
# artifacts, and whether /home/coder/logs has been created yet.
#
# Usage:
#   sudo ./scripts/check-workspace-startup.sh [workspace-container-name]
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

section "processes inside $WS"
docker exec "$DIND" docker exec "$WS" pgrep -af 'bash|startup|install|curl|apt|npm|nix' 2>&1 | head -20 || true

section "/tmp/coder-script-*.log tail"
docker exec "$DIND" docker exec "$WS" sh -c 'ls -t /tmp/coder-script-*.log 2>/dev/null | head -3' | while read -r f; do
  [[ -z "$f" ]] && continue
  echo "--- $f ---"
  docker exec "$DIND" docker exec "$WS" tail -n 20 "$f" 2>/dev/null || true
done

section "/home/coder contents (top-level)"
docker exec "$DIND" docker exec "$WS" ls -la /home/coder 2>&1 | head -20

section "/home/coder/logs (target for Loki)"
docker exec "$DIND" docker exec "$WS" ls -la /home/coder/logs 2>&1

section "/home/coder/bin/claude-run"
docker exec "$DIND" docker exec "$WS" ls -la /home/coder/bin/claude-run 2>&1

section "home volume on host"
HOME_VOL=$(docker exec "$DIND" docker inspect "$WS" --format '{{range .Mounts}}{{if eq .Destination "/home/coder"}}{{.Name}}{{end}}{{end}}')
echo "volume name: $HOME_VOL"
ls -la "/var/lib/docker/volumes/coder-dind_dind_data/_data/volumes/$HOME_VOL/_data/logs" 2>&1 | head -10 || true
