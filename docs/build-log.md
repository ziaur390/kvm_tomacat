# Build log

One entry per module. Raw commands, real output, and what broke.

| Module | What it delivers | Status |
|---|---|---|
| M0 | Repository scaffold | done |
| M1 | KVM host install + validation | done |
| M2 | Two VMs with fixed IPs | not started |
| M3 | Sample app WAR | not started |
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
