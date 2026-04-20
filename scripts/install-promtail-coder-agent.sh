#!/usr/bin/env bash
# Append a scrape_config for Coder workspace agent logs to promtail.
# Idempotent: does nothing if the job already exists.
#
# Usage:
#   sudo ./scripts/install-promtail-coder-agent.sh

set -euo pipefail

CONFIG=/etc/promtail/config.yml
BACKUP="$CONFIG.bak.$(date +%Y%m%d%H%M%S)"
JOB_NAME=coder-agent
HOST_LABEL=$(hostname)

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root (sudo $0)" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "error: $CONFIG not found" >&2
  exit 1
fi

if grep -q "job_name: $JOB_NAME" "$CONFIG"; then
  echo "coder-agent job already present in $CONFIG; nothing to do"
  exit 0
fi

cp "$CONFIG" "$BACKUP"
echo "backup: $BACKUP"

cat >>"$CONFIG" <<YAML
  - job_name: $JOB_NAME
    static_configs:
      - targets: [localhost]
        labels:
          job: $JOB_NAME
          host: $HOST_LABEL
          __path__: /var/lib/docker/volumes/coder-dind_dind_data/_data/volumes/coder-*-home/_data/logs/*.log
    pipeline_stages:
      - regex:
          source: filename
          expression: '/volumes/coder-(?P<workspace_id>[^/]+)-home/_data/logs/(?P<logfile>[^/]+)\$'
      - labels:
          workspace_id:
          logfile:
YAML

systemctl restart promtail
sleep 1
systemctl is-active --quiet promtail && echo "promtail: active" || {
  echo "promtail failed to start — see: journalctl -u promtail -n 30" >&2
  exit 1
}

journalctl -u promtail -n 10 --no-pager
