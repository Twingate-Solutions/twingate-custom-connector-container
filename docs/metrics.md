# Container Metrics

The container includes a built-in metrics emitter (`emit-metrics.sh`) that periodically samples CPU usage, memory consumption, and network I/O from the Linux kernel's cgroup filesystem and writes a structured JSON line to stdout every 60 seconds.

Because all output is written to stdout, any log aggregation tool already collecting the container's log stream — Datadog, CloudWatch Logs, Azure Monitor, Splunk, etc. — will automatically receive these metrics with no additional sidecar or agent required.

---

## Output Format

Each metrics emission is a single line following the same format as all other log output from this container:

```
[YYYY-MM-DD HH:MM:SS] [metrics] {json payload}
```

Example:

```
[2026-03-18 19:40:55] [metrics] {"ts":"2026-03-18T19:40:55Z","event":"metrics","cgroup_v":1,"iface":"eth0","cpu_pct":0.59,"mem_bytes":12238848,"mem_limit_bytes":null,"mem_pct":null,"net_rx_bytes_total":450793,"net_tx_bytes_total":234287,"net_rx_bytes_delta":448348,"net_tx_bytes_delta":234245,"interval_sec":60}
```

---

## JSON Field Schema

| Field | Type | Description |
|---|---|---|
| `ts` | string (ISO 8601 UTC) | Timestamp of the sample, in UTC |
| `event` | string | Always `"metrics"` — use this to filter metrics lines from application log lines |
| `cgroup_v` | integer | cgroup version in use on the host: `1` or `2` |
| `iface` | string | Network interface measured (first non-loopback interface, typically `eth0`) |
| `cpu_pct` | float | CPU usage as a percentage of one core over the sample interval. On a host with no CPU limit configured, this is unbounded (e.g. 200% on a two-core container using both cores fully). |
| `mem_bytes` | integer | Current memory usage in bytes |
| `mem_limit_bytes` | integer \| null | Memory limit in bytes as configured on the container. `null` if no limit is set. |
| `mem_pct` | float \| null | Memory usage as a percentage of `mem_limit_bytes`. `null` if no memory limit is configured. |
| `net_rx_bytes_total` | integer | Cumulative bytes received on `iface` since container start |
| `net_tx_bytes_total` | integer | Cumulative bytes transmitted on `iface` since container start |
| `net_rx_bytes_delta` | integer | Bytes received since the previous sample |
| `net_tx_bytes_delta` | integer | Bytes transmitted since the previous sample |
| `interval_sec` | integer | The sample interval in seconds (currently `60`) |

### Notes

- **CPU %** is computed by taking two snapshots of the kernel's cumulative CPU counter and dividing the delta by elapsed wall-clock time. It reflects CPU consumed by all processes inside the container.
- **Memory** is read from the cgroup memory controller. On hosts with no memory limit set for the container, `mem_limit_bytes` and `mem_pct` are `null`.
- **Network deltas** (`net_rx_bytes_delta`, `net_tx_bytes_delta`) are the most actionable fields for detecting traffic spikes. The total fields are useful for trending over time.
- **cgroup v1 vs v2**: The emitter auto-detects the cgroup version at startup. Modern Linux hosts (kernel 5.10+, including ECS Fargate 1.4+, AKS with recent node images, and Debian Bookworm) use cgroup v2. Older hosts (Amazon Linux 2, some EC2 instance types) use cgroup v1. Both are supported; the `cgroup_v` field tells you which is in use.

---

## Querying and Monitoring

### Local / Docker

Filter metrics lines out of the live log stream:

```bash
docker logs <container> 2>&1 | grep '"event":"metrics"'
```

Pretty-print the JSON payload in real time:

```bash
docker logs -f <container> 2>&1 | grep --line-buffered '"event":"metrics"' \
  | sed 's/^.*\[metrics\] //' \
  | python3 -m json.tool
```

---

### AWS ECS + CloudWatch Logs

When the ECS task definition uses the `awslogs` log driver, all container stdout is automatically delivered to a CloudWatch Logs log group. No additional configuration is required to receive metrics.

#### CloudWatch Logs Insights

Query the last hour of metrics samples:

```
fields @timestamp, @message
| filter @message like /\[metrics\]/
| parse @message /\[metrics\] (?<json>\{.+\})/
| fields
    fromMillis(1000 * toUnixTimestamp(datefloor(@timestamp, 1m))) as minute,
    json_extract_scalar(json, '$.cpu_pct')        as cpu_pct,
    json_extract_scalar(json, '$.mem_bytes')      as mem_bytes,
    json_extract_scalar(json, '$.mem_pct')        as mem_pct,
    json_extract_scalar(json, '$.net_rx_bytes_delta') as rx_delta,
    json_extract_scalar(json, '$.net_tx_bytes_delta') as tx_delta
| sort @timestamp desc
| limit 60
```

#### CloudWatch Logs Metric Filters

Metric filters extract numeric values from log lines and publish them as CloudWatch custom metrics, enabling CloudWatch Alarms and dashboards without writing any code.

Create a metric filter on your log group with the following filter pattern:

```
{ $.event = "metrics" }
```

Then add metric extractions for each field you want to track:

| CloudWatch Metric Name | Field | Unit |
|---|---|---|
| `ConnectorCpuPct` | `$.cpu_pct` | Percent |
| `ConnectorMemBytes` | `$.mem_bytes` | Bytes |
| `ConnectorMemPct` | `$.mem_pct` | Percent |
| `ConnectorNetRxDelta` | `$.net_rx_bytes_delta` | Bytes |
| `ConnectorNetTxDelta` | `$.net_tx_bytes_delta` | Bytes |

These metrics appear in the CloudWatch console under the namespace you specify. From there you can create alarms (e.g. alert when `ConnectorCpuPct` exceeds 80% for two consecutive periods) and build dashboards across connector instances.

> **Note**: CloudWatch Logs Metric Filters use `$.field` JSON selector syntax and require the JSON to appear at the top level of the log message. Because each metrics line is prefixed with `[datetime] [metrics]`, you need to confirm your filter pattern correctly identifies the right lines. Using `{ $.event = "metrics" }` is the most reliable selector since it matches on a field within the JSON body itself.

---

### Azure AKS + Log Analytics (Azure Monitor)

When Azure Monitor Container Insights is enabled on an AKS cluster, container stdout is automatically collected by the DaemonSet agent and stored in the `ContainerLogV2` table in your Log Analytics workspace.

#### Basic query

```kql
ContainerLogV2
| where LogMessage has "[metrics]"
| extend json = parse_json(extract(@"\[metrics\] (\{.+\})", 1, LogMessage))
| project
    TimeGenerated,
    cpu_pct         = todouble(json.cpu_pct),
    mem_bytes       = tolong(json.mem_bytes),
    mem_pct         = todouble(json.mem_pct),
    net_rx_delta    = tolong(json.net_rx_bytes_delta),
    net_tx_delta    = tolong(json.net_tx_bytes_delta)
| sort by TimeGenerated desc
```

#### Average CPU over time (binned by 5 minutes)

```kql
ContainerLogV2
| where LogMessage has "[metrics]"
| extend json = parse_json(extract(@"\[metrics\] (\{.+\})", 1, LogMessage))
| extend cpu_pct = todouble(json.cpu_pct)
| summarize avg_cpu = avg(cpu_pct) by bin(TimeGenerated, 5m)
| render timechart
```

#### Alert rule

Create a Log Analytics alert rule using a query such as:

```kql
ContainerLogV2
| where LogMessage has "[metrics]"
| extend json = parse_json(extract(@"\[metrics\] (\{.+\})", 1, LogMessage))
| extend cpu_pct = todouble(json.cpu_pct)
| where cpu_pct > 80
| summarize count() by bin(TimeGenerated, 5m)
```

Configure the alert to fire when result count exceeds 0 in the evaluation window.

---

### Datadog

Datadog's log pipeline processes container stdout automatically when the Datadog Agent is deployed (either as a DaemonSet on Kubernetes or using the Docker Agent with `DD_LOGS_ENABLED=true`).

#### Log Pipeline — JSON Remapper

In the Datadog Log Management console, create a processing pipeline for this container's logs:

1. Add a **Grok Parser** to extract the JSON payload from the log line:
   - **Name**: `Extract metrics JSON`
   - **Filter query**: `service:twingate-connector @message:[metrics]*` (adjust service name to match your configuration)
   - **Parsing rule**:
     ```
     metrics_line \[%{date("yyyy-MM-dd HH:mm:ss"):ts_local}\] \[metrics\] %{data::json}
     ```
   This promotes all JSON fields to first-class log attributes.

2. Add an **Attribute Remapper** to remap `event` → `@event_type` (optional, for filtering in dashboards).

Once parsed, fields such as `cpu_pct`, `mem_bytes`, and `net_rx_bytes_delta` appear as numeric attributes on every metrics log event.

#### Metrics from Logs

In **Logs → Generate Metrics**, create log-based metrics from the parsed attributes:

| Metric Name | Measure | Filter |
|---|---|---|
| `twingate.connector.cpu_pct` | `@cpu_pct` | `@event:metrics` |
| `twingate.connector.mem_bytes` | `@mem_bytes` | `@event:metrics` |
| `twingate.connector.net_rx_delta` | `@net_rx_bytes_delta` | `@event:metrics` |
| `twingate.connector.net_tx_delta` | `@net_tx_bytes_delta` | `@event:metrics` |

These become standard Datadog metrics you can graph in dashboards and alert on using monitors.

#### Example Monitor

Create a **Metric Monitor** on `twingate.connector.cpu_pct` with:
- **Evaluation window**: last 5 minutes
- **Alert threshold**: > 80
- **Warning threshold**: > 60
- **Message**: `Twingate connector on {{host.name}} is at {{value}}% CPU`

---

### Other Platforms (Splunk, Elastic, etc.)

Any platform that ingests container stdout can work with these metrics. The key points:

- Filter lines containing `[metrics]` or `"event":"metrics"` to isolate metrics entries from application log lines
- Extract the JSON substring starting from `{` to the end of the line
- Parse it as JSON — all numeric fields (`cpu_pct`, `mem_bytes`, etc.) are ready to use as measures
- Use `net_rx_bytes_delta` and `net_tx_bytes_delta` for per-interval traffic; use `net_rx_bytes_total` / `net_tx_bytes_total` for cumulative trending
- The `ts` field (UTC ISO 8601) can be used as an authoritative event timestamp if your ingestion pipeline adds its own timestamp at a different granularity
