# Build log

One entry per module. Raw commands, real output, and what broke.

| Module | What it delivers | Status |
|---|---|---|
| M0 | Repository scaffold | done |
| M1 | KVM host install + validation | done |
| M2 | Two VMs with fixed IPs | done |
| M3 | Sample app WAR | done |
| M4 | Ansible roles + idempotency proof | done |
| M5 | Snapshots + live resize | done |
| M6 | Verified backup + restore drill | done |
| M7 | Monitoring + capacity plan | not started |
| M8 | Firewall hardening (optional) | not started |
| M9 | README, screenshots, resume | not started |

## Environment

- Host: Windows 11 Pro, 20 GB RAM, 8 cores exposed to WSL2
- Guest host: WSL2 Ubuntu 24.04.3 LTS, systemd PID 1, `/dev/kvm` present
- Repo lives at `~/kvm-tomcat-lab` inside WSL (native ext4, not `/mnt/c`)
- Git remote: `git@github.com:ziaur390/kvm_tomacat.git`

## M0 - Repository scaffold

`git init -b main`, committed `.gitignore`, README stub and `docs/screenshots/`.
Direct push to `main` for the initial commit only; every module from M1 onward
lands through a feature branch and a pull request.

## M1 - KVM host install + validation

Detailed notes: [host-setup.md](host-setup.md)

- Installed qemu, libvirt, virtinst, cpu-checker, zip; enabled `libvirtd`.
- `kvm-ok` reports "KVM acceleration can be used" - nested virt works in WSL2.
- Added the user to `libvirt` and `kvm`; restarted the distro to apply groups.
  `virsh` then works without sudo.
- Downloaded and checksum-verified the noble cloud image (597 MB).

### What broke

After the distro restart the `default` network would not start:
`Network is already in use by interface virbr0`. WSL keeps the kernel alive
across a distro restart, so `virbr0` survived while `libvirtd` did not, and the
new daemon will not adopt a bridge it did not create.

Fix: `sudo ip link delete virbr0 && virsh net-start default`. Documented in
[host-setup.md](host-setup.md) because it will recur after every WSL restart.

## M2 - Two VMs with fixed IPs

- Generated `~/.ssh/kvmlab` (ed25519, no passphrase - lab only).
- `scripts/create-vms.sh` reserves the two addresses by MAC in libvirt's DHCP
  and creates both domains from the cloud image, with `maxvcpus`/`maxmemory`
  set for the later live resize in M5.
- Both VMs boot, get their reserved addresses, and accept key-only SSH as `ops`.
- `ansible all -m ping` succeeds against both.

```
$ virsh list --all
 Id   Name    State
 1    app01   running
 2    web01   running

$ virsh net-dhcp-leases default
 192.168.122.11/24   52:54:00:aa:00:11   app01
 192.168.122.12/24   52:54:00:aa:00:12   web01

$ ssh ops@192.168.122.11 'hostname && nproc && free -m | head -2'
app01
1
Mem:  1867 total  1433 free
```

The `2048 MiB is less than the recommended 3072 MiB` warning from virt-install
is deliberate: app01 is undersized so the M7 load test has a bottleneck.

### What broke

1. The stale `virbr0` bit again while installing packages, so the reservations
   step failed with `network is not running`. Because it kept recurring, the
   one-line fix became a permanent one: a systemd `ExecStartPre` running
   `scripts/libvirt-clear-stale-bridge.sh`, guarded so it only fires when no
   qemu domain is running.
2. `ansible-galaxy collection install community.general` pulled 13.4.0 into
   `~/.ansible/collections`, which warns that it does not support ansible-core
   2.16.3 - and that user path shadows the supported 8.3.0 that the apt
   `ansible` package already ships in
   `/usr/lib/python3/dist-packages/ansible_collections`. Removed the user copy;
   no galaxy install is needed on this host.

## M3 - Sample app WAR

Three tiny files and a build script:

- `app/src/health.jsp` - returns `OK <hostname>`, used by Ansible's deployment
  health check and by every "is it up" question later.
- `app/src/work.jsp` - burns CPU in a loop on purpose. M7's load test needs an
  endpoint that actually saturates a vCPU; a page that just prints text would
  leave nothing to measure.
- `app/src/WEB-INF/web.xml` - maps `/health` and `/work` onto those JSPs, so the
  URLs do not end in `.jsp`.
- `app/build.sh` - zips `src/` into `roles/tomcat/files/labapp.war`.

```
$ bash app/build.sh
built ../../roles/tomcat/files/labapp.war
      Length      Name
          96      health.jsp
         162      work.jsp
         554      WEB-INF/web.xml
```

`build.sh` fails if `WEB-INF/web.xml` is missing from the archive. Without that
guard the symptom in Tomcat is a confusing 404 rather than a broken build.

Deploys as context `/labapp`, so the endpoints are `/labapp/health` and
`/labapp/work`. A named context avoids fighting Tomcat's built-in ROOT app.

TODO (M7): the loop count of 3,000,000 is a guess. Measure the response time
under `ab` and tune it so one request costs roughly 50-100 ms.

## M4 - Ansible roles, deploy and idempotency proof

Four roles: `common` (apt cache, curl, htop), `node_exporter` (the metrics
agent for M7), `tomcat` (WebLogic-style app tier), `apache` (reverse proxy).

### First run

```
PLAY RECAP
app01  : ok=10  changed=4  failed=0
web01  : ok=14  changed=9  failed=0
```

The Tomcat health check retried twice before passing. That is expected, not a
bug: the first request to a JSP makes Tomcat compile it, which takes a few
seconds. Hence `retries: 12 delay: 5` rather than a single attempt.

### The deployment works

```
$ curl http://192.168.122.12/labapp/health     # through Apache on web01
OK app01

$ curl http://192.168.122.11:8080/labapp/health   # direct to Tomcat
OK app01
```

Two things worth noting. The response is `OK app01` while the URL pointed at
`web01` - the hostname in the body is the app machine's, which proves the
request really was proxied rather than served locally. And the same URL works
directly on 8080, which is what M8 will close off with ufw.

### Second run - idempotency proof

```
PLAY RECAP
app01  : ok=10  changed=0  failed=0
web01  : ok=12  changed=0  failed=0
```

`changed=0` means every task checked the actual state of the machine and found
nothing to do. That is what idempotent means, and it is the difference between
configuration management and a shell script.

### What broke

1. **A rebuilt WAR was never byte-identical.** Running `app/build.sh` twice with
   no source changes produced two different archives, so the `Deploy the lab WAR`
   copy task reported `changed` on every run and the idempotency proof was a
   lie waiting to be exposed. Cause: Info-ZIP writes extra metadata (including
   high-precision timestamps) into the archive. Fix: `zip -X`.

   ```
   before -X:  d6432034986adb0e...
   after  -X:  2e2a19812c6e926f...
   ```

   After the fix, two rebuilds hash identically, and the playbook reports
   `changed=1` for the new WAR and then `changed=0` on the run after that.
   Worth knowing: an idempotency claim is only as good as the artifact you feed
   it.

2. `a2dissite` replaced the guide's "delete the symlink with the `file` module"
   step. Deleting a symlink by path is a footgun, and the `removes:` guard makes
   the real tool report `ok` instead of `changed` on later runs.

## M5 - Snapshots, rollback and live resizing

Full write-up: [snapshots-and-resize.md](snapshots-and-resize.md)

- Took a `clean-deploy` snapshot, recorded the WAR sha256, deleted the deployed
  app (`HTTP 404` through Apache), reverted, and confirmed the WAR returned with
  the identical hash.
- The revert took 5.1 s and did **not** reboot the guest (uptime `up 1 minute`
  before and after), so it is a memory-state rollback rather than a disk
  restore plus boot.
- Live resize: memory `1867 MB -> 2891 MB` inside the guest with no reboot. Two
  vCPUs were added at the hypervisor but the guest kept `nproc=1` - the kernel
  logged `ACPI: CPU1 has been hot-added` and left it offline, so it had to be
  onlined by hand. The guide's `nproc` verification step would have failed here
  as written.
- Exceeding the creation-time ceiling fails loudly: `setvcpus 5` and `setmem 8G`
  are both rejected with errors naming the maximums.

### What broke

1. **The WSL idle shutdown was power-cycling the guests**, hard-killing qemu and
   restarting the VMs. Three boots in twelve minutes, plus an SSH session that
   died mid-command. Fixed with `vmIdleTimeout=-1` in `C:\Users\ziaur\.wslconfig`
   and verified with a 150 second idle test (uptime `25s -> 184s`).
2. **The stale-bridge guard could never be false.** `pgrep -x
   qemu-system-x86_64` never matches because Linux truncates process names to 15
   characters, so the negation was always true and the script would have deleted
   `virbr0` on every `libvirtd` start, including with live VMs. Replaced with a
   check of the bridge's own port list.
3. **A dropped SSH connection silently looked like an empty directory.** The
   destructive `rm` had worked, but the listing before it printed nothing
   because the connection dropped and stderr went to `/dev/null`. That sent me
   chasing a lost-write theory for several turns. The real story was duller:
   every later playbook run failed against guests that were still booting, so
   nothing was ever redeployed. Checksums at every step settled it. Lesson: do
   not swallow stderr on the command that is supposed to prove something.

## M6 - Backup with a verified restore

Full write-up: [backup-and-restore.md](backup-and-restore.md)

- `tomcat-backup.sh` archives `webapps/`, extracts the archive into a scratch
  directory, hashes the restore, compares it against a manifest of the source,
  and exits non-zero on any disagreement.
- Real run: `RESTORE VERIFIED: 5 files match`, plus a 7-day retention sweep and
  a nightly systemd timer with `Persistent=true`.
- `scripts/backup-failure-drill.sh` tampers with a manifest, asserts the
  verifier rejects it with exit code 1, then restores the manifest and asserts
  it passes. Both outcomes are asserted, so the drill fails if the verification
  ever silently breaks.
- `scripts/pull-backups.sh` rsyncs the archives to the KVM host and re-checks
  the checksum that was computed on the VM.

### Deliberate addition beyond the guide

The script refuses to back up an empty source directory. Two empty manifests
compare equal, so the guide's version as written would print
`RESTORE VERIFIED: 0 files match` for a deployment directory containing nothing.
That is not theoretical: `webapps/` really was empty for a while during M5, and
an unguarded tool would have "verified" a night of meaningless backups.

### Environment note: a persistent WSL session is required

Root cause of the churn in M5, finally pinned down. WSL tears down the distro
when the last session exits. That stops `libvirtd`, which takes qemu with it, so
the guests are power-cycled and only come back because of autostart.

Evidence: the kernel messages `Linux version 6.18.40.1-microsoft-standard-WSL2`
and `mini_init: WSL user cgroup created` repeat between commands, while
`/proc/uptime` and `boot_id` carry on regardless - because the WSL VM kernel
stays alive and only the distro is torn down. `vmIdleTimeout=-1` does not help,
because this is session-driven, not idle-driven.

Workaround, verified: hold a session open.

```bash
nohup wsl.exe -e bash -c "sleep 3600" >/dev/null 2>&1 &
```

With that running, qemu process start times and `libvirtd`'s start time stayed
identical across a 90 second gap and the guests stopped rebooting. Without it,
the guests were rebooted between almost every command.

### Follow-up after the revert

Roughly a minute after the memory-state revert the guest rebooted by itself, the
last log line being `systemd-resolved: Clock change detected`. A memory restore
rewinds the guest clock and invalidates in-flight I/O, so the guest notices.

Ruled out the scary explanation: the guest does **not** arm the itco watchdog
(`RuntimeWatchdogUSec=0`), so a watchdog reset is not the cause. That mattered to
check, because an armed watchdog firing under load would have silently corrupted
the M7 capacity numbers.
