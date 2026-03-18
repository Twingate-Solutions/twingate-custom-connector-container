#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/twingate/connector.conf"
CONFIG_DIR=$(dirname "$CONFIG")

log_with_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_with_timestamp "[entrypoint] Starting entrypoint script..."

: "${TWINGATE_ACCESS_TOKEN:?required}"
: "${TWINGATE_REFRESH_TOKEN:?required}"
: "${TWINGATE_NETWORK:?required}"

log_with_timestamp "[entrypoint] Configuring Twingate connector..."

mkdir -p "${CONFIG_DIR}"

{
  echo "TWINGATE_NETWORK=${TWINGATE_NETWORK}"
  echo "TWINGATE_ACCESS_TOKEN=${TWINGATE_ACCESS_TOKEN}"
  echo "TWINGATE_REFRESH_TOKEN=${TWINGATE_REFRESH_TOKEN}"
  echo "TWINGATE_LABEL_DEPLOYED_BY=custom_docker_connector_v1"
  if [ -n "${TWINGATE_LOG_ANALYTICS:-}" ]; then
    echo "TWINGATE_LOG_ANALYTICS=${TWINGATE_LOG_ANALYTICS}"
  fi
  if [ -n "${TWINGATE_LOG_LEVEL:-}" ]; then
    echo "TWINGATE_LOG_LEVEL=${TWINGATE_LOG_LEVEL}"
  fi
} > "${CONFIG}"

chmod 0600 "${CONFIG}"

# If arguments were provided, run them after config and exit.
# This enables: docker run IMAGE sh -lc 'twingate-connector --version'
if [ "$#" -gt 0 ]; then
  log_with_timestamp "[entrypoint] Running command: $*"
  exec "$@"
fi

log_with_timestamp "[entrypoint] Starting metrics emitter..."
/usr/local/bin/emit-metrics.sh &

log_with_timestamp "[entrypoint] Starting Twingate connector..."

# systemd normally creates this via RuntimeDirectory=twingate and sets TWINGATE_API_ENDPOINT.
# Without systemd we do it ourselves so twingate-connectorctl can reach the running connector.
mkdir -p /run/twingate
export TWINGATE_API_ENDPOINT=/run/twingate/connector.sock

exec twingate-connector
