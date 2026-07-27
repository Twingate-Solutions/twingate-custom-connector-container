#!/usr/bin/env bash
set -euo pipefail

# Healthcheck output has to reach two places:
#   1. Our own stdout — Docker's healthcheck capture, visible via `docker inspect`.
#   2. PID 1's stdout — Docker does not forward healthcheck output to the container
#      log, so writing to /proc/1/fd/1 is what makes it show up in `docker logs`.
#
# This is done with an in-shell emit() rather than `exec 1> >(tee /proc/1/fd/1)`.
# Process substitution forks a `tee` that this script never reaps: the script's shell
# exits first, the orphaned `tee` is reparented onto PID 1 (the connector binary, which
# is not an init and does not reap adopted children), and it stays a zombie forever.
# That leaks one PID per HEALTHCHECK interval for the life of the container.
# emit() forks nothing, and the per-check pipeline below is waited on normally.

# Best effort: if /proc/1/fd/1 is not writable (non-Docker use, restricted procfs,
# PID 1's stdout closed), mirroring is dropped and output still reaches Docker's
# health capture, and the exit code is still recorded correctly either way.
MIRROR=/proc/1/fd/1
[ -w "$MIRROR" ] || MIRROR=/dev/null

emit() {
  printf '%s\n' "$1"
  printf '%s\n' "$1" >>"$MIRROR" 2>/dev/null || true
}

log_with_timestamp() {
  emit "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

FAILED=0

for f in /healthchecks.d/*.sh; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || chmod +x "$f"

  log_with_timestamp "[healthchecks] Running $f..."

  # Pipe the check through emit line by line. Same dual-destination output as before,
  # still streamed live rather than buffered until the check exits (so partial output
  # survives a HEALTHCHECK timeout), but the subshell is a foreground pipeline member
  # that this shell waits on, so nothing is left unreaped. pipefail propagates the
  # check's exit status; the `|| [ -n "$line" ]` flushes a final unterminated line.
  if "$f" 2>&1 | while IFS= read -r line || [ -n "$line" ]; do emit "$line"; done; then
    log_with_timestamp "[healthchecks] $f OK"
  else
    log_with_timestamp "[healthchecks] $f FAILED"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  log_with_timestamp "[healthchecks] One or more checks failed. Marking container unhealthy."
  exit 1
fi
