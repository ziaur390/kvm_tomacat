# KVM host setup

Module M1. The "host" for this lab is a **WSL2 Ubuntu 24.04 distro** on Windows
11 Pro using nested virtualization, not a bare-metal Ubuntu box. That is the
weakest of the three options in the project guide (bare metal > Ubuntu VM with
nested virt > WSL2), so it is worth writing down what that costs.

## Environment

| Thing | Value |
|---|---|
| Windows host | Windows 11 Pro, 19.8 GB RAM |
| WSL distro | Ubuntu 24.04.3 LTS (`noble`), systemd as PID 1 |
| CPUs visible to WSL | 8 |
| RAM visible to WSL | ~9.6 GB |
| Free disk | ~950 GB |
| `/dev/kvm` | present, `crw-rw---- root kvm` |
| Repo path | `~/kvm-tomcat-lab` (native ext4) |

### Why the repo is not on `/mnt/c`

The repo lives in the WSL filesystem, not in the Windows project folder.

- `git` over the 9p/drvfs bridge to `/mnt/c` is slow and mangles file modes.
- Windows-side OneDrive sync fighting `.git` corrupts repositories.
- `ansible-playbook` and `qemu-img` want a normal POSIX filesystem.

Windows can still read it at `\\wsl.localhost\Ubuntu\home\ziaur26261\kvm-tomcat-lab`.

### Why WSL2 nested virtualization

Nested virt means the KVM guests run inside the WSL2 Hyper-V VM. It works
because Windows exposes virtualization extensions to WSL2 (on by default on
current Windows 11 builds), and the WSL2 kernel ships the KVM modules.

Costs, stated honestly:

- guest CPU is slower than bare metal, so the M7 capacity numbers are
  *relative*, not absolute;
- total RAM available to the guests is capped at roughly 9.6 GB, because WSL2
  defaults to 50% of physical memory;
- a WSL restart does not clean up libvirt's bridge interface (see the quirk
  below).

## Packages installed

```bash
sudo apt-get install -y qemu-system-x86 qemu-utils \
  libvirt-daemon-system libvirt-clients virtinst cpu-checker zip
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"      # then restart the distro
```

`zip` is needed by `app/build.sh`. `cpu-checker` provides `kvm-ok`.

Group membership only applies to a new login session, so the distro was
restarted with `wsl.exe --terminate Ubuntu` — the WSL equivalent of logging
out and back in. After that `virsh` works without `sudo`:

```
uid=1000(ziaur26261) groups=...,111(libvirt),993(kvm)
```

## Validation

```
$ sudo kvm-ok
INFO: /dev/kvm exists
KVM acceleration can be used

$ systemctl is-active libvirtd
active

$ virsh net-list
 Name      State    Autostart   Persistent
--------------------------------------------
 default   active   yes         yes

$ ping -c 2 192.168.122.1
2 packets transmitted, 2 received, 0% packet loss
```

The `default` libvirt network is a NAT network on `192.168.122.0/24` with the
host as gateway `192.168.122.1`. Guests reach the internet and each other
through it; the host reaches guests directly.

## Fixed addresses

DHCP reservations by MAC, created by `scripts/create-vms.sh`. Fixed addresses
mean the Ansible inventory never changes.

| VM | IP | MAC | Role | Shape |
|---|---|---|---|---|
| app01 | 192.168.122.11 | 52:54:00:aa:00:11 | Tomcat 10 | 1 vCPU / 2 GB, max 4 vCPU / 4 GB |
| web01 | 192.168.122.12 | 52:54:00:aa:00:12 | Apache 2.4 | 1 vCPU / 1 GB, no headroom |

Each VM's 10 GB disk is a qcow2 overlay on the shared 597 MB base image, so the
base is stored once. `qemu-img info` shows the `backing file:` line.

Access is key-only as the `ops` user (`sudo` with no password, so Ansible can
use `become`), using the lab key `~/.ssh/kvmlab`. Password auth is disabled in
cloud-init.

## Cloud-init

No installer runs. `virt-install --import` boots the cloud image directly and
feeds it a seed ISO with a `#cloud-config` that sets the hostname, creates
`ops`, and installs the SSH public key. First boot completes in seconds.

## Cloud image

```bash
cd /var/lib/libvirt/images
sudo wget -O noble-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sudo wget -O SHA256SUMS \
  https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
sudo grep 'noble-server-cloudimg-amd64.img$' SHA256SUMS | sudo sha256sum -c -
```

```
noble-server-cloudimg-amd64.img: OK
```

597 MB, checksum verified against the publisher's `SHA256SUMS`. An unverified
base image is the kind of thing that is only noticed months later.

## WSL quirk: stale `virbr0` blocks the network after a restart

Restarting the distro (`wsl --terminate`, `wsl --shutdown`, or Windows sleep)
leaves the `virbr0` bridge behind, because WSL keeps the VM kernel running while
only the distro's init is restarted. The new `libvirtd` then refuses to bring up
the network:

```
error: Failed to start network default
error: internal error: Network is already in use by interface virbr0
```

`virsh net-start default` will not fix it. Delete the orphaned bridge first:

```bash
sudo ip link delete virbr0
virsh net-start default
```

### Permanent fix

`scripts/libvirt-clear-stale-bridge.sh` is installed as an `ExecStartPre` for
`libvirtd.service`, so `virbr0` is cleared automatically before the daemon
starts:

```bash
sudo install -m 0755 scripts/libvirt-clear-stale-bridge.sh /usr/local/bin/
sudo mkdir -p /etc/systemd/system/libvirtd.service.d
printf '%s\n' '[Service]' \
  'ExecStartPre=/usr/local/bin/libvirt-clear-stale-bridge.sh' \
  | sudo tee /etc/systemd/system/libvirtd.service.d/10-wsl-stale-bridge.conf
sudo systemctl daemon-reload
```

The guard matters. The script deletes the bridge only when nothing is attached
to it, checking `/sys/class/net/virbr0/brif`. If any interface is a bridge port,
a domain is live and the bridge is left alone. An unconditional delete would rip
the network out from under running VMs.

An earlier version of the guard used `pgrep -x qemu-system-x86_64`, which can
never match anything: Linux truncates process names to 15 characters, so the
process is `qemu-system-x86` and the negation was always true. That guard looked
correct, reviewed correctly, and would have deleted the bridge on every
dependency restart. Testing it against a running VM is what caught it:

```
$ pgrep -x qemu-system-x86_64 ; echo $?
1                       <-- never matches, so "! pgrep" was always true
$ ls -A /sys/class/net/virbr0/brif
vnet0 vnet1             <-- real state: two live domains attached
```

### WSL idle shutdown

WSL shuts down its utility VM when idle, which hard-kills qemu and power-cycles
the guests. They autostart again, but an unflushed guest write can be lost, and
an SSH session can die mid-command. Disabled in `C:\Users\ziaur\.wslconfig`:

```ini
[wsl2]
vmIdleTimeout=-1
```

After that change WSL survived a 150 second idle window with no WSL processes
running (uptime `25s` before, `184s` after) and both domains stayed up.

This is a WSL-only artifact. On a real Ubuntu host, rebooting destroys `virbr0`
with the rest of the network namespace, so neither problem exists.

Verify the network self-heals after a distro restart:

```bash
virsh net-list --all && ping -c1 192.168.122.1
```
