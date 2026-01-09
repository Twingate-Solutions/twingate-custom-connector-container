#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/twingate/connector.conf"
CONFIG_DIR=$(dirname "$CONFIG")

log_with_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

log_with_timestamp "[entrypoint] Starting entrypoint script..."
log_with_timestamp "[entrypoint] Installing Twingate connector..."

: "${TWINGATE_ACCESS_TOKEN:?required}"
: "${TWINGATE_REFRESH_TOKEN:?required}"
: "${TWINGATE_NETWORK:?required}"

# Install the Twingate Connector
apt update -yq
apt_require_curl
apt_require_gpg
TWINGATE_GPG_PUBLIC_KEY=/usr/share/keyrings/twingate-connector-keyring.gpg
if ! curl -fsSL "https://packages.twingate.com/apt/gpg.key" | gpg --dearmor -o "$TWINGATE_GPG_PUBLIC_KEY"; then
    echo "Failed to download or process GPG key"
    exit 1
fi
echo "deb [signed-by=${TWINGATE_GPG_PUBLIC_KEY}] https://packages.twingate.com/apt/ /" | tee /etc/apt/sources.list.d/twingate.list
apt update -yq
apt install -yq twingate-connector

if [ -n "${TWINGATE_NETWORK}" ]; then
  echo "TWINGATE_NETWORK=${TWINGATE_NETWORK}" >> "${CONFIG}"
elif [ -n "${TWINGATE_URL}" ]; then
  echo "TWINGATE_URL=${TWINGATE_URL}" >> "${CONFIG}"
fi

if [ -n "${TWINGATE_ACCESS_TOKEN}" ] && [ -n "${TWINGATE_REFRESH_TOKEN}" ]; then
    { \
        echo "TWINGATE_ACCESS_TOKEN=${TWINGATE_ACCESS_TOKEN}"; \
        echo "TWINGATE_REFRESH_TOKEN=${TWINGATE_REFRESH_TOKEN}"; \
    } >> "${CONFIG}"
    if [ -n "${TWINGATE_LOG_ANALYTICS}" ]; then
        echo "TWINGATE_LOG_ANALYTICS=${TWINGATE_LOG_ANALYTICS}" >> "${CONFIG}"
    fi
    chmod 0600 "$CONFIG"
    systemctl enable --now twingate-connector
fi

echo "TWINGATE_LABEL_DEPLOYED_BY=custom_docker_connector_v1" | sudo tee -a /etc/twingate/connector.conf

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
exec twingate-connector

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