#!/usr/bin/env bash
set -euo pipefail

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