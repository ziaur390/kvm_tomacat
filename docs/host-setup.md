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

597 MB, checksum verified against the publisher's `SHA256SUMS`. The checksum
check matters: an unverified base image is the kind of thing that is only
noticed months later.

The image is used as a **qcow2 backing file**, so each VM's 10 GB disk starts
as a thin overlay and the 597 MB base is stored once. This is the same
mechanism as a VMware linked clone or a Hyper-V differencing disk.

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

This is a WSL-only artifact. On a real Ubuntu host, rebooting destroys `virbr0`
with the rest of the network namespace, so the problem does not exist. Do not
"fix" this with a systemd `ExecStartPre` that always deletes `virbr0`: that
would tear the network out from under running VMs on an ordinary
`systemctl restart libvirtd`.

Run this check at the start of a work session:

```bash
virsh net-list --all && ping -c1 192.168.122.1
```
