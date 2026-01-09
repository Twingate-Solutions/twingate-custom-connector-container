#!/usr/bin/env bash
set -euo pipefail

log_with_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

log_with_timestamp "[entrypoint] Starting entrypoint script..."
log_with_timestamp "[entrypoint] Installing Twingate connector..."

: "${TWINGATE_ACCESS_TOKEN:?required}"
: "${TWINGATE_REFRESH_TOKEN:?required}"
: "${TWINGATE_NETWORK:?required}"

curl -fsSL https://binaries.twingate.com/connector/setup.sh | TWINGATE_ACCESS_TOKEN="$TWINGATE_ACCESS_TOKEN" TWINGATE_REFRESH_TOKEN="$TWINGATE_REFRESH_TOKEN" TWINGATE_NETWORK="$TWINGATE_NETWORK" TWINGATE_LABEL_DEPLOYED_BY="custom_docker_connector_v1" bash

if [ "$TWINGATE_LOG_ANALYTICS" ]; then
  echo "Enabling detailed traffic logging"
  echo "TWINGATE_LOG_ANALYTICS=$TWINGATE_LOG_ANALYTICS" | sudo tee -a /etc/twingate/connector.conf
fi

if [ "$TWINGATE_LOG_LEVEL" == "7" ]; then
  echo "Setting log level to $TWINGATE_LOG_LEVEL"
  echo "TWINGATE_LOG_LEVEL=7" | sudo tee -a /etc/twingate/connector.conf
else
  echo "TWINGATE_LOG_LEVEL=$TWINGATE_LOG_LEVEL" | sudo tee -a /etc/twingate/connector.conf
fi

log_with_timestamp "[entrypoint] Starting Twingate connector container..."
systemctl restart twingate-connector.service

log_with_timestamp "[entrypoint] Twingate started. Keeping container running."
log_with_timestamp "[entrypoint] Forwarding Twingate log to stdout..."

# Filter common syslog files for twingate-related entries and forward them to stdout
SYSLOG_CANDIDATES=("/var/log/syslog" "/var/log/messages" "/var/log/daemon.log")
for s in "${SYSLOG_CANDIDATES[@]}"; do
if [ -e "$s" ]; then
    log_with_timestamp "[entrypoint] Forwarding twingate entries from $s to stdout..."
    tail -F "$s" | grep --line-buffered -E "twingate|twingated|twingate-connector" &
    break
fi
done

# Keep container alive; twingate runs as a daemon
sleep infinity