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

    # Capture and pattern-match in-shell instead of `twingate-connectorctl health | grep -q OK`.
    # `grep -q` exits the instant it matches, so a connector still writing output takes
    # SIGPIPE and exits 141 — and under `pipefail` that non-zero status becomes the
    # pipeline's status, turning a healthy connector into a failed check, five wasted
    # retries, and a container marked unhealthy. Latent today (the health output fits in
    # the 64 KB pipe buffer, so connectorctl finishes writing before grep reads) but the
    # blast radius is a false unhealthy that orchestrators act on.
    #
    # `|| true` keeps errexit from killing the script when the connector is genuinely
    # down: as before, only the presence of "OK" in the output decides the check.
    health_output=$(twingate-connectorctl health 2>&1) || true

    if [[ "$health_output" == *"OK"* ]]; then
        log_with_timestamp "[healthcheck] Twingate is 'OK'."
        exit 0
    else
        log_with_timestamp "[healthcheck] Twingate is not online. Retrying in $SLEEP_BETWEEN seconds..."
        sleep "$SLEEP_BETWEEN"
    fi
done

log_with_timestamp "[healthcheck] Twingate did not become online after $MAX_RETRIES attempts."
exit 1