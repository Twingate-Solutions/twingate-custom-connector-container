#!/usr/bin/env bash
# emit-metrics.sh — Emits container resource metrics as a JSON line to stdout
# every INTERVAL seconds. Tagged with event="metrics" for filtering in log
# aggregators (CloudWatch Logs, Datadog, etc.).
#
# Supports cgroup v1 and v2 — version is auto-detected at startup.
# CPU %:    fraction of a single core; may exceed 100% on multi-core hosts with no CPU limit.
# Mem %:    null when no memory limit is configured.
# Network:  first non-loopback interface; byte deltas are floored to 0 on counter reset.

INTERVAL=60

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [metrics] $*"
}

# ── cgroup version detection ──────────────────────────────────────────────────
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    CGVER=2
else
    CGVER=1
fi

log "Starting (cgroup v${CGVER}, interval ${INTERVAL}s)"

# ── readers ───────────────────────────────────────────────────────────────────

# Cumulative CPU time consumed by this cgroup, in microseconds
read_cpu_usec() {
    if [ "$CGVER" -eq 2 ]; then
        awk '/^usage_usec/ {print $2; exit}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo "0"
    else
        # v1 cpuacct.usage is nanoseconds; convert to microseconds
        awk '{printf "%d\n", $1/1000}' /sys/fs/cgroup/cpuacct/cpuacct.usage 2>/dev/null || echo "0"
    fi
}

# Current memory usage in bytes
read_mem_bytes() {
    if [ "$CGVER" -eq 2 ]; then
        cat /sys/fs/cgroup/memory.current 2>/dev/null || echo "0"
    else
        cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo "0"
    fi
}

# Memory limit in bytes, or 0 if unlimited
read_mem_limit() {
    local val
    if [ "$CGVER" -eq 2 ]; then
        val=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        [ "$val" = "max" ] && echo "0" || echo "$val"
    else
        val=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
        # cgroup v1 uses near-max int64 (~9.2e18) to mean unlimited
        if [ "$val" -gt 9000000000000000000 ] 2>/dev/null; then
            echo "0"
        else
            echo "$val"
        fi
    fi
}

# "iface rx_bytes tx_bytes" for the first non-loopback interface
read_net() {
    awk 'NR>2 {
        gsub(/:/, "", $1)
        if ($1 != "lo") { print $1, $2, $10; exit }
    }' /proc/net/dev 2>/dev/null || echo "unknown 0 0"
}

# ── initial samples ───────────────────────────────────────────────────────────
cpu_prev=$(read_cpu_usec)
wall_prev=$(date +%s)
read -r iface rx_prev tx_prev <<< "$(read_net)"

# ── emit loop ─────────────────────────────────────────────────────────────────
while true; do
    sleep "$INTERVAL"

    cpu_now=$(read_cpu_usec)
    wall_now=$(date +%s)
    mem_bytes=$(read_mem_bytes)
    mem_limit=$(read_mem_limit)
    read -r iface rx_now tx_now <<< "$(read_net)"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ts_local=$(date '+%Y-%m-%d %H:%M:%S')

    # Integer deltas — bash arithmetic is exact for integers
    cpu_delta=$(( cpu_now  - cpu_prev  ))
    wall_delta=$(( wall_now - wall_prev ))
    rx_delta=$(( rx_now - rx_prev ))
    tx_delta=$(( tx_now - tx_prev ))

    # Floor to zero on counter reset or measurement anomaly
    [ "$cpu_delta"  -lt 0 ] && cpu_delta=0
    [ "$rx_delta"   -lt 0 ] && rx_delta=0
    [ "$tx_delta"   -lt 0 ] && tx_delta=0
    [ "$wall_delta" -le 0 ] && wall_delta=1   # guard against divide-by-zero

    awk \
        -v ts="$ts" \
        -v ts_local="$ts_local" \
        -v cgver="$CGVER" \
        -v iface="$iface" \
        -v cpu_delta="$cpu_delta" \
        -v wall_delta="$wall_delta" \
        -v mem_bytes="$mem_bytes" \
        -v mem_limit="$mem_limit" \
        -v rx_now="$rx_now"   -v rx_delta="$rx_delta" \
        -v tx_now="$tx_now"   -v tx_delta="$tx_delta" \
        -v interval="$INTERVAL" \
    'BEGIN {
        # cpu_delta is µs of CPU time; wall_delta is seconds
        cpu_pct = (cpu_delta / (wall_delta * 1000000)) * 100

        if (mem_limit > 0) {
            mem_limit_field = mem_limit
            mem_pct_field   = sprintf("%.2f", (mem_bytes / mem_limit) * 100)
        } else {
            mem_limit_field = "null"
            mem_pct_field   = "null"
        }

        printf "[%s] [metrics] {\"ts\":\"%s\",\"event\":\"metrics\",\"cgroup_v\":%d,\"iface\":\"%s\",\"cpu_pct\":%.2f,\"mem_bytes\":%d,\"mem_limit_bytes\":%s,\"mem_pct\":%s,\"net_rx_bytes_total\":%d,\"net_tx_bytes_total\":%d,\"net_rx_bytes_delta\":%d,\"net_tx_bytes_delta\":%d,\"interval_sec\":%d}\n",
            ts_local, ts, cgver, iface, cpu_pct, mem_bytes, mem_limit_field, mem_pct_field,
            rx_now, tx_now, rx_delta, tx_delta, interval
    }'

    # Rotate samples for next iteration
    cpu_prev=$cpu_now
    wall_prev=$wall_now
    rx_prev=$rx_now
    tx_prev=$tx_now
done
