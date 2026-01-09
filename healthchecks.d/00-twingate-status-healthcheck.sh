#!/usr/bin/env bash
# Check if Twingate connector is online

# This is a very straight-forward and basic healthcheck that simply runs
# `twingate-connectorctl health` and looks for the "OK" status. If found,
# the healthcheck passes. If not, it retries a few times before failing.
set -euo pipefail

# Healthcheck parameters
MAX_RETRIES=5
SLEEP_BETWEEN=5

log_with_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

# Main healthcheck loop
for i in $(seq 1 "$MAX_RETRIES"); do
    log_with_timestamp "[healthcheck] Checking Twingate status (attempt $i of $MAX_RETRIES)..."
    if twingate-connectorctl health | grep -q "OK"; then
        log_with_timestamp "[healthcheck] Twingate is 'OK'."
        exit 0
    else
        log_with_timestamp "[healthcheck] Twingate is not online. Retrying in $SLEEP_BETWEEN seconds..."
        sleep "$SLEEP_BETWEEN"
    fi
done

log_with_timestamp "[healthcheck] Twingate did not become online after $MAX_RETRIES attempts."
exit 1