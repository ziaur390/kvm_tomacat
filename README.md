# kvm-tomcat-lab

A two-tier Java application tier built on KVM virtual machines: Apache
reverse-proxies to Tomcat 10. Provisioned with idempotent Ansible, protected by
snapshots and a checksum-verified backup, monitored with Prometheus and Grafana,
and sized with a measured load test rather than a guess.

Everything below is measured output from this lab. The raw output behind each
claim is in [`docs/evidence/`](docs/evidence/) and can be regenerated with
`bash scripts/capture-evidence.sh`.

> **Just want to understand it?** There is a 42-page plain-English study guide
> that explains every tool in this project - what it is, why it was needed, how
> it is used here, and where you will meet it in a real job - starting from zero
> assumed knowledge. Read the PDF: **[kvm-tomcat-lab-study-guide.pdf](docs/kvm-tomcat-lab-study-guide.pdf)**, or the
> Markdown sources in [`docs/study-guide/`](docs/study-guide/) (rebuild with
> `bash docs/study-guide/build-pdf.sh`).

## Architecture

```
Windows 11 host - Intel i5-1155G7, 4 cores / 8 threads, 20 GB RAM
└── WSL2 Ubuntu 24.04 (nested virtualisation, /dev/kvm available)
    ├── KVM / libvirt
    │   └── NAT network 192.168.122.0/24
    │       ├── web01  192.168.122.12   Apache 2.4     1 vCPU / 1 GB
    │       └── app01  192.168.122.11   Tomcat 10      1-4 vCPU / 2-4 GB
    │                                   labapp.war     maxvcpus 4 set at creation
    └── Prometheus 3.15.0 + Grafana 13.2.3  (host networking, scrapes :9100)
```

Request path: client → `web01:80` (Apache) → `app01:8080` (Tomcat) → `labapp`.
Only `web01:80` is reachable from outside the lab; `app01:8080` is firewalled to
the web tier, which is what makes the reverse proxy load-bearing rather than
decorative.

`app01` is deliberately built undersized at 1 vCPU. That is not an oversight - it
exists so the load test has a bottleneck to find and a scaling story to tell.

## Measured results

| Claim | Result | Evidence |
|---|---|---|
| Ansible is idempotent | second run: `app01 changed=0`, `web01 changed=0` | [01](docs/evidence/01-idempotency.txt) |
| Apache proxies to Tomcat | `curl` through web01 → `OK app01` | [02](docs/evidence/02-proxy-vs-direct.txt) |
| Tomcat is not directly reachable | `app01:8080` from the host: HTTP 000, curl exit 28 (dropped) | [02](docs/evidence/02-proxy-vs-direct.txt) |
| Backup restores, not just archives | `RESTORE VERIFIED: 5 files match` | [03](docs/evidence/03-backup-restore-verified.txt) |
| Backup verification rejects a bad backup | tampered manifest → `RESTORE MISMATCH`, exit 1 | [04](docs/evidence/04-backup-failure-drill.txt) |
| Backup exists off the VM | 2 archives in `~/kvm-lab-backups`, `sha256sum -c` OK | [05](docs/evidence/05-offvm-copy.txt) |
| Snapshot rollback | 5.1 s revert, no reboot, content hash unchanged | [snapshots](docs/snapshots-and-resize.md) |
| Live resize | memory hot-added live; a hot-added vCPU stays offline until onlined | [07](docs/evidence/07-live-resize.txt) |
| Monitoring | 2 targets `up`, 4 alert rules, dashboard imported by script | [08](docs/evidence/08-monitoring.txt) |
| **Recovery from total VM loss** | **348 s (5 min 48 s) to a working service** | [disaster-recovery](docs/disaster-recovery.md) |

Snapshots (KVM console, `virsh list` and `dominfo`) - see
[docs/screenshots/](docs/screenshots/).

## Capacity planning

`bash scripts/capacity-test.sh` hot-adds vCPUs, onlines them inside the guest,
and runs `ab -n 2000 -c 20` against `/labapp/work` at each size. Peak CPU is read
back from Prometheus rather than eyeballed off a graph.

| app01 vCPUs | guest `nproc` | req/sec | p95 | app01 CPU | web01 CPU | host CPU |
|---|---|---|---|---|---|---|
| 1 | 1 | 17.93 | 1497 ms | 100% | 14% | 16% |
| 2 | 2 | 29.18 | 971 ms | 100% | 14% | 31% |
| 4 | 4 | 44.14 | 761 ms | 100% | 14% | 56% |

4x the CPUs bought **2.46x** the throughput, and p95 improved **2.0x**.

What the table rules out, which is the more useful half of the result:

- **app01 is the bottleneck.** Its CPU is pinned at 100% at every size, so the
  application really is CPU-bound.
- **The proxy tier is not the constraint.** web01 sits at 14% regardless.
- **The host is not exhausted**, rising 16% → 56% and never saturating, so the
  flattening is not "out of machine" and the load generator is not the limit.
- **The host is 4 physical cores with SMT.** At 4 vCPUs, app01 occupies every
  physical core, sharing them with the load generator, Apache, Prometheus and
  Grafana. Sibling hyperthreads share execution units, which explains why the
  3rd and 4th vCPU add less than the 1st and 2nd.

What the data cannot separate: shared-core contention from the JVM's own serial
parts (GC, single-threaded components). Both produce the same curve, and telling
them apart needs the JMX exporter.

**Measurement honesty:** the same experiment run twice differed by a consistent
~20% per data point (14.71 / 23.88 / 36.65 once, 17.93 / 29.18 / 44.14 again),
which is systematic rather than noise. The *shape* reproduced and is the finding;
the absolute requests per second are indicative, not precise. Full analysis in
[capacity-planning.md](docs/capacity-planning.md).

## Reproduce

Requires a host with virtualization support. Steps 1-3 take about 20 minutes.

```bash
# 1. KVM host: qemu, libvirt, virtinst, cloud image. See docs/host-setup.md
sudo apt-get install -y qemu-system-x86 qemu-utils libvirt-daemon-system \
  libvirt-clients virtinst cpu-checker zip
sudo systemctl enable --now libvirtd

# 2. Two VMs with fixed addresses, from the cloud image
bash scripts/create-vms.sh

# 3. Build the WAR and configure both VMs
bash app/build.sh
ansible-playbook site.yml

# 4. The application answers, through the proxy
curl http://192.168.122.12/labapp/health
# OK app01
```

Optional extras:

```bash
cd monitoring && docker compose up -d          # Prometheus :9090, Grafana :3000
bash monitoring/import-dashboard.sh            # Node Exporter Full (ID 1860)
bash scripts/capture-evidence.sh               # regenerate docs/evidence/
bash scripts/capacity-test.sh                  # the capacity table above
bash scripts/backup-failure-drill.sh           # prove the backup checker fails
```

## Snapshot versus backup

Interviewers ask this every time.

A **snapshot** is a point-in-time state that lives on the same storage as the VM.
It is for fast rollback before a risky change. It does not protect you from
losing the disk - which this project demonstrates literally: the disaster
recovery drill destroys `app01` with `--remove-all-storage`, and the
`clean-deploy` snapshot dies with it.

A **backup** is an independent copy stored elsewhere and verified. It is for
disaster recovery. Here that means an archive of the deployment, a SHA-256
manifest, a restore-to-scratch comparison, and a copy pulled off the VM whose
checksum is re-checked after the transfer.

## How this maps to VMware and Hyper-V

The lab used KVM. These are the equivalents, and being clear about which tooling
was actually used is stronger than implying experience that does not exist.

| KVM/libvirt (used here) | vSphere | Hyper-V |
|---|---|---|
| `virsh snapshot-create-as` | VM snapshot | Checkpoint |
| `virsh snapshot-revert` | Revert to snapshot | Apply checkpoint |
| `virsh setvcpus/setmem --live` | Hot-add CPU/memory | Dynamic Memory, processor change |
| qcow2 backing-file overlay | Linked clone | Differencing disk |
| `maxvcpus` / `maxmemory` at creation | VM limits fixed at creation | Startup/maximum RAM |
| libvirt `default` NAT network | Standard vSwitch / port group | Virtual switch (NAT/internal) |
| `virsh migrate` | vMotion | Live Migration |

## Lessons learned

Five real things broke. The full list, including the ones that cost hours, is in
[the build log](docs/build-log.md).

**1. A guard that can never be false is not a guard.** A WSL restart leaves
libvirt's `virbr0` bridge behind, which blocks the network coming up, so a script
deletes the stale bridge before `libvirtd` starts - guarded by
`pgrep -x qemu-system-x86_64`. Linux truncates process names to 15 characters, so
that pattern matches nothing, the negation is always true, and the "safety" check
would have deleted the network out from under running VMs. Replaced with a check
of the bridge's own attached ports. It looked correct in review; only testing it
against a live VM caught it.

**2. An idempotency claim is only as good as the artifact.** `zip` writes extra
metadata, so rebuilding an unchanged WAR produced a different file, the Ansible
copy task reported `changed` forever, and the `changed=0` proof was quietly
false. `zip -X` fixed it. The lesson generalises: verify that the thing you feed
into an idempotency check is itself reproducible.

**3. WSL tears down the distro when the last session exits.** That stops
`libvirtd`, which takes qemu with it, so the guests were power-cycled between
almost every command and my work kept vanishing. Found by noticing that kernel
boot messages repeated while `boot_id` and `/proc/uptime` carried on unchanged -
the VM kernel stays alive, only the distro is torn down. Fixed by holding a
session open, and verified by watching process start times stop changing.

**4. An empty directory archives and verifies perfectly.** Two empty manifests
compare equal, so a backup tool without a guard prints `RESTORE VERIFIED: 0 files
match` for a deployment directory containing nothing. The deployment really was
empty for a while during this build, so the guard against it is in the tool.

**5. Never swallow stderr on the command that is supposed to prove something.**
A destructive command had worked, but the listing before it printed nothing
because the SSH connection dropped and the error went to `/dev/null`. An empty
output looked exactly like an empty directory, and I spent several turns chasing
a lost-write theory that did not exist.

## Limitations

Stated plainly, because a portfolio project that lists no weaknesses is not
credible:

- **Single host, no high availability.** One app VM. If `app01` is down, the site
  is down; the firewall is not redundancy.
- **Absolute performance numbers describe a laptop.** Nested virtualisation on an
  i5-1155G7 with 4 physical cores. The method and the shape of the scaling curve
  are the transferable parts.
- **The off-VM backup copy is on the same physical machine.** It survives losing
  the VM, not losing the host.
- **The backup covers the deployment, not the machine.** In this lab the WAR is
  also in git, so the backup is not the only recovery path - a truer test would
  involve state that git does not hold.
- **SSH is open to any address** and there is no TLS on port 80. Both are
  deliberate so the lab stays reachable; [hardening.md](docs/hardening.md) lists
  these and the other gaps.
- **Lab-grade settings** that would not ship: host key checking disabled in
  `ansible.cfg`, Grafana on `admin/admin`, no secrets management.
- **Not tested on VMware or Hyper-V.** The concepts map (see the table above),
  but the tooling used was KVM.

## Repository layout

```
.
├── ansible.cfg, inventory.ini, site.yml
├── app/                     health.jsp, work.jsp, web.xml, build.sh -> labapp.war
├── roles/
│   ├── common/              apt cache, curl, htop, rsync
│   ├── tomcat/              Tomcat 10, deploys the WAR, health-checked
│   ├── apache/              reverse proxy vhost
│   ├── backup/              verified backup script, systemd service + timer
│   ├── node_exporter/       metrics agent
│   └── hardening/           ufw rules matching the two-tier design
├── monitoring/              Prometheus, Grafana, alert rules, dashboard import
├── scripts/                 create-vms, capacity-test, evidence, DR helpers
└── docs/
    ├── kvm-tomcat-lab-study-guide.pdf   plain-English guide to every tool used
    ├── study-guide/         the study guide sources, one file per chapter
    ├── build-log.md         module-by-module log, including what broke
    ├── host-setup.md        KVM host install and the WSL quirks
    ├── snapshots-and-resize.md
    ├── backup-and-restore.md
    ├── capacity-planning.md
    ├── hardening.md
    ├── disaster-recovery.md
    ├── interview-notes.md   the questions this project prepares you for
    └── evidence/            raw output behind every claim in this README
```

## Definition of done

- [x] Both VMs run and are reachable over key-only SSH
- [x] `ansible-playbook site.yml` twice, second run `changed=0`
- [x] `curl` via Apache returns `OK app01`
- [x] Snapshot taken, deliberate breakage, revert works (5.1 s)
- [x] Live vCPU/memory resize shown with `nproc` and `free -m`
- [x] Backup shows `RESTORE VERIFIED`; tamper drill shows `RESTORE MISMATCH`
- [x] Backup copied to the host and checksum-verified
- [x] Prometheus targets UP, Grafana dashboard working
- [x] Load test table filled in with real numbers
- [x] Disaster recovery drill: total VM loss to working service in 348 s
- [x] README complete with a real "Lessons learned"
- [x] Study guide written for someone starting from zero (42 pages)

## Stack

KVM / libvirt, cloud-init, qcow2, Ansible, Apache 2.4, Tomcat 10 (Jakarta EE),
JSP, systemd timers, tar/SHA-256 integrity verification, rsync, Prometheus,
Grafana, ufw, bash.

Built on Ubuntu 24.04 LTS.

## License

Apache License 2.0. See [LICENSE](LICENSE).
