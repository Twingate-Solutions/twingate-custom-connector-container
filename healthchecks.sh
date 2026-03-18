#!/usr/bin/env bash
set -euo pipefail

# Mirror all output to PID 1's stdout so healthcheck messages appear in docker logs.
# Docker captures healthcheck subprocess output separately (visible via docker inspect),
# but does not forward it to the container log. Writing to /proc/1/fd/1 bridges the gap.
# tee passes output through to its own stdout (Docker's capture) AND writes to /proc/1/fd/1.
# The 2>/dev/null on tee is best-effort: if /proc/1/fd/1 is unavailable, output still
# reaches Docker's health capture and the exit code is still recorded correctly.
exec 1> >(tee /proc/1/fd/1 2>/dev/null) 2>&1

FAILED=0

log_with_timestamp() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@"
}

for f in /healthchecks.d/*.sh; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || chmod +x "$f"

  log_with_timestamp "[healthchecks] Running $f..."
  if ! "$f"; then
    log_with_timestamp "[healthchecks] $f FAILED"
    FAILED=1
  else
    log_with_timestamp "[healthchecks] $f OK"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  log_with_timestamp "[healthchecks] One or more checks failed. Marking container unhealthy."
  exit 1
fi