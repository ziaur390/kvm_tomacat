#!/usr/bin/env bash
#
# Regenerates docs/evidence/ - the raw output behind the claims in the README.
#
# Text rather than screenshots wherever the proof is textual, so it is greppable,
# diffable and does not depend on anyone's terminal theme. Grafana is the one
# exception, because a graph is the evidence there.
#
# Run this after a change and commit the result; the README links into these
# files so a reader can check a number instead of trusting it.
#
#   bash scripts/capture-evidence.sh
#
set -uo pipefail

cd "$(dirname "$0")/.."
OUT=docs/evidence
mkdir -p "$OUT"

KEY="$HOME/.ssh/kvmlab"
SSHOPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"
APP=192.168.122.11
WEB=192.168.122.12

hdr() { printf '### %s\n### captured %s\n\n' "$1" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; }

echo "==> 01 idempotency (two playbook runs)"
{
  hdr "Two consecutive ansible-playbook runs. The second must report changed=0."
  echo "\$ ansible-playbook site.yml   # run 1"
  ansible-playbook site.yml 2>&1 | sed -n '/PLAY RECAP/,$p'
  echo
  echo "\$ ansible-playbook site.yml   # run 2"
  ansible-playbook site.yml 2>&1 | sed -n '/PLAY RECAP/,$p'
} > "$OUT/01-idempotency.txt" 2>&1

echo "==> 02 proxy vs direct"
{
  hdr "The reverse proxy is load-bearing: the app answers through web01 and is
unreachable directly from the host, which is not on the allow list."
  echo "\$ curl http://$WEB/labapp/health          # through Apache on web01"
  curl -s -m 15 "http://$WEB/labapp/health"; echo
  echo
  echo "\$ curl http://$APP:8080/labapp/health     # direct to Tomcat, bypassing the proxy"
  curl -s -o /dev/null -m 6 -w 'HTTP %{http_code} (curl exit %{exitcode})\n' "http://$APP:8080/labapp/health"
  echo "  exit 28 = timed out, i.e. dropped by the firewall rather than refused"
  echo
  echo "\$ sudo ufw status verbose   # on app01"
  ssh $SSHOPTS "ops@$APP" "sudo ufw status verbose" 2>/dev/null
  echo
  echo "\$ sudo ufw status   # on web01"
  ssh $SSHOPTS "ops@$WEB" "sudo ufw status" 2>/dev/null
} > "$OUT/02-proxy-vs-direct.txt" 2>&1

echo "==> 03 backup restore verification"
{
  hdr "Backing up shows the restore being verified, not just the archive created."
  ssh $SSHOPTS "ops@$APP" "sudo systemctl start tomcat-backup.service; sleep 3; \
    sudo journalctl -u tomcat-backup.service -n 20 --no-pager" 2>/dev/null
  echo
  echo "\$ sudo ls -la /var/backups/tomcat/"
  ssh $SSHOPTS "ops@$APP" "sudo ls -la /var/backups/tomcat/" 2>/dev/null
  echo
  echo "\$ systemctl list-timers tomcat-backup.timer"
  ssh $SSHOPTS "ops@$APP" "systemctl list-timers tomcat-backup.timer --no-pager" 2>/dev/null
} > "$OUT/03-backup-restore-verified.txt" 2>&1

echo "==> 04 backup failure drill"
{
  hdr "Proof the verification discriminates: a tampered manifest is rejected with
a non-zero exit code, and the same archive passes again once restored."
  bash scripts/backup-failure-drill.sh 2>&1
} > "$OUT/04-backup-failure-drill.txt" 2>&1

echo "==> 05 off-VM copy"
{
  hdr "The backup exists outside the VM it protects, and the checksum computed on
the VM is re-checked after the transfer."
  bash scripts/pull-backups.sh 2>&1
  echo
  echo "\$ ls -la ~/kvm-lab-backups/"
  ls -la "$HOME/kvm-lab-backups/"
} > "$OUT/05-offvm-copy.txt" 2>&1

echo "==> 06 VM shape and snapshots"
{
  hdr "VM inventory, resources, and the snapshot used for rollback."
  echo "\$ virsh list --all"
  virsh list --all
  echo
  echo "\$ virsh dominfo app01"
  virsh dominfo app01
  echo
  echo "\$ virsh snapshot-list app01"
  virsh snapshot-list app01
  echo
  echo "\$ virsh net-dhcp-leases default"
  virsh net-dhcp-leases default
  echo
  echo "\$ ssh ops@$APP 'hostname; nproc; free -m'"
  ssh $SSHOPTS "ops@$APP" "hostname; nproc; free -m" 2>/dev/null
} > "$OUT/06-vm-shape.txt" 2>&1

echo "==> 07 live resize"
{
  hdr "Live CPU and memory resize, and the failure mode where a hot-added vCPU
stays offline until the guest is told to online it."
  echo "\$ virsh dominfo app01 | grep -E '^CPU\(s\)|Used memory'    # before"
  virsh dominfo app01 | grep -E '^CPU\(s\)|Used memory'
  echo "\$ ssh ops@$APP 'nproc'"
  ssh $SSHOPTS "ops@$APP" "nproc" 2>/dev/null
  echo
  echo "\$ virsh setvcpus app01 2 --live; virsh setmem app01 3G --live"
  virsh setvcpus app01 2 --live && echo "  setvcpus ok"
  virsh setmem app01 3G --live && echo "  setmem ok"
  sleep 4
  echo
  echo "\$ ssh ops@$APP 'nproc'    # still 1: ACPI hot-added CPU1 and left it offline"
  ssh $SSHOPTS "ops@$APP" "nproc; cat /sys/devices/system/cpu/present; cat /sys/devices/system/cpu/online" 2>/dev/null
  echo
  echo "\$ ssh ops@$APP 'echo 1 | sudo tee /sys/devices/system/cpu/cpu1/online; nproc'"
  ssh $SSHOPTS "ops@$APP" "echo 1 | sudo tee /sys/devices/system/cpu/cpu1/online >/dev/null; nproc" 2>/dev/null
  echo
  echo "\$ virsh setmem app01 3G --live   -> visible inside the guest"
  ssh $SSHOPTS "ops@$APP" "free -m | sed -n 2p" 2>/dev/null
  echo
  echo "\$ virsh setvcpus app01 5 --live    # past the maximum fixed at creation"
  virsh setvcpus app01 5 --live 2>&1
  echo "\$ virsh setmem app01 8G --live"
  virsh setmem app01 8G --live 2>&1
  echo
  echo "# restoring the documented shape"
  virsh setvcpus app01 1 --live
  virsh setmem app01 2G --live
} > "$OUT/07-live-resize.txt" 2>&1

echo "==> 08 monitoring"
{
  hdr "Prometheus scrape targets, loaded alert rules, and Grafana health."
  echo "\$ curl -s localhost:9090/api/v1/targets"
  curl -s -m 10 http://localhost:9090/api/v1/targets | python3 -c '
import json, sys
for t in json.load(sys.stdin)["data"]["activeTargets"]:
    print("  %-22s job=%-6s health=%s" % (t["labels"]["instance"], t["labels"]["job"], t["health"]))
'
  echo
  echo "\$ curl -s localhost:9090/api/v1/rules"
  curl -s -m 10 http://localhost:9090/api/v1/rules | python3 -c '
import json, sys
for g in json.load(sys.stdin)["data"]["groups"]:
    for r in g["rules"]:
        print("  %-14s state=%s" % (r["name"], r.get("state", "?")))
'
  echo
  echo "\$ curl -s localhost:3000/api/health"
  curl -s -m 10 http://localhost:3000/api/health
  echo
  echo "\$ curl -s -u admin:admin 'localhost:3000/api/search?type=dash-db'"
  curl -s -m 10 -u admin:admin "http://localhost:3000/api/search?type=dash-db" | python3 -c '
import json, sys
for d in json.load(sys.stdin):
    print("  %s (uid=%s)" % (d["title"], d["uid"]))
'
} > "$OUT/08-monitoring.txt" 2>&1

echo
echo "Written to $OUT:"
ls -1 "$OUT"
