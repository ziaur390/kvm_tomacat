#!/usr/bin/env bash
#
# Capacity-planning experiment: throughput against app01's vCPU count.
#
# For each vCPU count it hot-adds CPU to the running VM, onlines it inside the
# guest, runs the same load test through Apache, and records requests/sec, p95
# latency and app01's peak CPU over the test window.
#
# app01 is deliberately built with maxvcpus 4 (see scripts/create-vms.sh), which
# is what makes the hot-add possible at all.
#
#   bash scripts/capacity-test.sh            # sweeps 1, 2, 4 vCPU
#   N=500 C=10 bash scripts/capacity-test.sh 9
#
# Load is generated with ab from the host, so the host must have spare CPU for
# the results to describe app01 rather than the load generator.

set -euo pipefail

APP_IP=192.168.122.11
WEB_IP=192.168.122.12
PROM=${PROM:-http://localhost:9090}
URL="http://$WEB_IP/labapp/work"

N=${N:-2000}   # total requests per run
C=${C:-20}     # concurrency
VCPUS=${*:-"1 2 4"}

KEY="$HOME/.ssh/kvmlab"
SSH="ssh -i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 ops@$APP_IP"

guest_nproc() {
  $SSH 'nproc' 2>/dev/null
}

# A hot-added vCPU stays offline in this guest (the kernel logs "ACPI: CPU1 has
# been hot-added" and stops there), and nproc counts online CPUs only. Onlining
# it explicitly is the difference between the test measuring 1 CPU and 2.
online_cpus() {
  $SSH 'for i in 1 2 3; do
          if [ -e "/sys/devices/system/cpu/cpu$i/online" ]; then
            echo 1 | sudo tee "/sys/devices/system/cpu/cpu$i/online" >/dev/null
          fi
        done
        nproc' 2>/dev/null
}

# Peak CPU% for one instance across the test window, read back from Prometheus
# rather than eyeballed off a graph.
peak_cpu() { # peak_cpu <instance>
  curl -s --max-time 10 -G "$PROM/api/v1/query" --data-urlencode \
    "query=max_over_time((100 - avg by (instance) (rate(node_cpu_seconds_total{instance=\"$1:9100\",mode=\"idle\"}[1m])) * 100)[8m:15s])" \
    | python3 -c '
import json, sys
result = json.load(sys.stdin)["data"]["result"]
if not result:
    print("n/a")
else:
    print("%.0f%%" % float(result[0]["value"][1]))
'
}

# The load generator runs on the host and shares the same 8 physical cores as
# both VMs, so host saturation has to be measured, not assumed. Reads total and
# idle jiffies from /proc/stat.
host_cpu_snapshot() {
  awk '/^cpu / { total=0; for (i=2; i<=8; i++) total+=$i; print total, $5+$6 }' /proc/stat
}

host_cpu_busy_pct() { # host_cpu_busy_pct <before> <after>
  read -r t1 i1 <<< "$1"
  read -r t2 i2 <<< "$2"
  awk -v t1="$t1" -v i1="$i1" -v t2="$t2" -v i2="$i2" \
    'BEGIN { printf "%.0f%%", 100 * (1 - (i2 - i1) / (t2 - t1)) }'
}

set_vcpus() {
  virsh setvcpus app01 "$1" --live
}

printf '%-6s %-8s %-10s %-9s %-9s %-8s %s\n' vCPUs nproc 'req/sec' p95 'app01cpu' 'web01cpu' 'hostcpu'
printf '%s\n' '----------------------------------------------------------------------------'

for n in $VCPUS; do
  set_vcpus "$n" >/dev/null
  sleep 3
  online_cpus >/dev/null || true
  sleep 2
  np=$(guest_nproc)

  # Warm up so the first measured request is not paying JSP compilation, then
  # give Prometheus a scrape or two before the window starts.
  curl -s -o /dev/null --max-time 60 "$URL"
  sleep 5

  host_before=$(host_cpu_snapshot)
  ab -n "$N" -c "$C" "$URL" > "/tmp/ab-$n.txt" 2>&1
  host_after=$(host_cpu_snapshot)

  rps=$(awk '/Requests per second/ {print $4}' "/tmp/ab-$n.txt")
  p95=$(awk '$1=="95%" {print $2}' "/tmp/ab-$n.txt")
  failed=$(awk '/Failed requests/ {print $3}' "/tmp/ab-$n.txt")

  printf '%-6s %-8s %-10s %-9s %-9s %-8s %s\n' "$n" "$np" "$rps" "${p95}ms" \
    "$(peak_cpu "$APP_IP")" "$(peak_cpu "$WEB_IP")" "$(host_cpu_busy_pct "$host_before" "$host_after")"
  [ "$failed" = "0" ] || echo "  WARNING: $failed failed requests" >&2
done

# Leave the lab in its documented shape: 1 vCPU / 2 GB.
set_vcpus 1 >/dev/null
online_cpus >/dev/null || true
echo
echo "app01 returned to $(virsh dominfo app01 | awk '/^CPU\(s\)/ {print $2}') vCPU"
