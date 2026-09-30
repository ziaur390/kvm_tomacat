# Build log

One entry per module. Raw commands, real output, and what broke.

| Module | What it delivers | Status |
|---|---|---|
| M0 | Repository scaffold | done |
| M1 | KVM host install + validation | done |
| M2 | Two VMs with fixed IPs | done |
| M3 | Sample app WAR | done |
| M4 | Ansible roles + idempotency proof | not started |
| M5 | Snapshots + live resize | not started |
| M6 | Verified backup + restore drill | not started |
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
