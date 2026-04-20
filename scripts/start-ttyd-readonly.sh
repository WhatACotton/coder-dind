#!/usr/bin/env bash
# Launch a second ttyd on port 7682 as a read-only live view of a screen
# session. By default it attaches to session "build" in multi-attach mode
# (screen -x) so the interactive ttyd on 7681 keeps working.
#
# Usage:
#   sudo ./scripts/start-ttyd-readonly.sh [session-name] [workspace-container-name]
#
# session-name defaults to "build". Pass a session that actually exists, or
# use "tail" to fall back to tail -F on the latest screen-*.log.

set -uo pipefail
set -x

SESSION=${1:-build}
WS=${2:-coder-whatacotton-rtl-dev}
DIND=coder-dind-dind-1

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

# If session name is "tail", stream the most recent screen-*.log instead of attaching.
if [[ "$SESSION" == "tail" ]]; then
  CMD='bash -lc "tail -n 500 -F $(ls -t /home/coder/logs/screen-*.log | head -1)"'
else
  CMD="screen -x $SESSION"
fi

docker exec "$DIND" docker exec -u coder "$WS" bash -c "
  pid=\$(ss -tlnp 2>/dev/null | awk '/:7682 /{sub(\".*pid=\",\"\",\$NF); sub(\",.*\",\"\",\$NF); print \$NF; exit}')
  [[ -n \"\$pid\" ]] && kill \"\$pid\" 2>/dev/null && sleep 1
  mkdir -p /home/coder/logs
  setsid nohup ttyd \\
    --port 7682 \\
    --interface 0.0.0.0 \\
    --credential \"\$(cat /home/coder/.ttyd-auth)\" \\
    $CMD >/home/coder/logs/ttyd-ro.log 2>&1 < /dev/null &
  echo \"ttyd-ro pid: \$!\"
  sleep 1
  echo '--- ttyd-ro.log ---'
  cat /home/coder/logs/ttyd-ro.log 2>&1 || true
  echo '--- pgrep ---'
  pgrep -af ttyd 2>&1 || echo '(no ttyd)'
  echo '--- port check ---'
  ss -tlnp 2>/dev/null | grep -E '7681|7682' || netstat -tlnp 2>/dev/null | grep -E '7681|7682' || echo '(nothing)'
"
