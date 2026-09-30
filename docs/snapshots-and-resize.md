# Snapshots, rollback and live resizing

Module M5. Everything below is measured output from this lab, not theory.

## Snapshot versus backup

Interviewers ask this every time, so here is the answer this project can defend.

| | Snapshot | Backup |
|---|---|---|
| Where it lives | Same storage as the VM (`/var/lib/libvirt/images`) | Somewhere else entirely |
| Good for | Fast rollback before a risky change | Disaster recovery |
| Survives losing the VM disk | **No** - it dies with the disk | Yes, that is the point |
| Includes RAM | Optionally, as done here | No, it is a file archive |
| Verified | Not applicable | Restored to scratch and checksum-compared (M6) |

A snapshot is not a backup. A backup is not a snapshot. This lab has both, and
M6 proves the backup restores.

## Snapshot and rollback drill

```bash
virsh snapshot-list app01
virsh snapshot-create-as app01 clean-deploy \
  --description "Tomcat 10 + labapp deployed, WAR sha256 9e6fe29b..."
```

The project guide warns that `snapshot-create-as` can fail on a cloud image
because of the cloud-init seed device. It did not fail here, because the seed
ISO is already detached after first boot - `virsh domblklist app01` shows `sda`
as an empty cdrom, so only the `vda` qcow2 is involved.

The WAR checksum was recorded at snapshot time, then the deployment was
destroyed deliberately:

```bash
$ ssh ops@192.168.122.11 'sudo rm -rf /var/lib/tomcat10/webapps/*'

through Apache:   HTTP 404
direct to Tomcat: HTTP 404
```

404 rather than 503 is the correct symptom: Tomcat is healthy, the `/labapp`
context no longer exists. (A 503 would have meant Tomcat itself was down -
worth knowing, because it is how you tell "app broken" from "app server
broken" at 3am.)

Then the revert:

```bash
$ time virsh snapshot-revert app01 clean-deploy
Domain snapshot clean-deploy reverted
real  0m5.119s
```

**The revert did not reboot the machine.** Guest uptime was `up 1 minute`
immediately before the revert and `up 1 minute` immediately after it, and the
WAR came back with the same sha256 as before the damage:

```
guest WAR sha256: 9e6fe29bc4f1cf2a0739b84e6c528a35ba34880b60fe5874670e0e1fa340769a
local WAR sha256: 9e6fe29bc4f1cf2a0739b84e6c528a35ba34880b60fe5874670e0e1fa340769a
```

That is a memory-state rollback (`loadvm`), not a disk restore plus boot. The
domain resumed at the exact instant the snapshot was taken, which is why
recovery took five seconds instead of the two to three minutes a guest boot
costs in this environment.

One client-visible wrinkle: the first request after the revert returned a `502
Proxy Error`, and the next five returned `200 OK`. The restored JVM and Apache's
pooled upstream connection need a moment to agree. A rollback is near-instant
but not atomic from the client's point of view - worth saying out loud rather
than claiming a clean cutover.

## Live resizing

`maxvcpus` and `maxmemory` were fixed when the domain was created in M2. That is
the whole reason live resize is possible at all.

Baseline before the change:

```
CPU(s):         1
Max memory:     4194304 KiB
Used memory:    2097152 KiB
guest: nproc=1, Mem: 1867 MB
```

```bash
virsh setvcpus app01 2 --live
virsh setmem  app01 3G --live
```

Memory worked immediately and visibly inside the guest, with no reboot:

```
CPU(s):         2
Used memory:    3145728 KiB
guest: nproc=1, Mem: 2891 MB      <-- 1867 -> 2891 MB
```

CPU did **not** work end to end. libvirt reported 2 vCPUs, but the guest still
said 1:

```
$ ssh ops@192.168.122.11 'cat /sys/devices/system/cpu/online'   # 0
$ ssh ops@192.168.122.11 'cat /sys/devices/system/cpu/present'  # 0-1
$ ssh ops@192.168.122.11 'sudo dmesg | grep -i hot'
[  130.977897] ACPI: CPU1 has been hot-added
```

So the kernel received the ACPI hotplug event, created the CPU, and left it
**offline**. `nproc` counts online CPUs, which is why the guide's verification
step as written would have failed on this machine.

The usual reason is that `systemd-udevd` onlines hot-added CPUs via
`40-vm-hotadd.rules`. That file is present and `systemd-udevd` is active here,
so the uevent was simply missed - a known rough edge of nested virtualization.
The fix is one line:

```bash
echo 1 | sudo tee /sys/devices/system/cpu/cpu1/online   # now nproc=2
```

`setvcpus` back down to 1 does work live, so a resize can be undone.

## The ceiling is real

This is the interview answer for "how does live resize work". The maximums are
fixed at creation and everything happens underneath them:

```
$ virsh setvcpus app01 5 --live
error: invalid argument: requested vcpus is greater than max allowable vcpus
       for the live domain: 5 > 4

$ virsh setmem app01 8G --live
error: invalid argument: cannot set memory higher than max memory
```

## Mapping to VMware and Hyper-V

KVM/libvirt is what this lab used. The concepts transfer:

| KVM/libvirt (what was done here) | vSphere | Hyper-V |
|---|---|---|
| `virsh snapshot-create-as` | VM snapshot | Checkpoint |
| `virsh snapshot-revert` | Revert to snapshot | Apply checkpoint |
| `virsh setvcpus/setmem --live` | Hot-add CPU/memory | Dynamic Memory, processor change |
| qcow2 backing-file overlay | Linked clone | Differencing disk |
| `maxvcpus` / `maxmemory` at creation | VM limits fixed at creation | Startup/maximum RAM |
| libvirt `default` NAT network | Standard vSwitch / port group | Virtual switch (NAT/internal) |
| `virsh migrate` | vMotion | Live Migration |

Being clear that the tooling was KVM and that these are the equivalents is
stronger than implying hands-on vSphere experience.

## Environment hazard: WSL power-cycles the guests

Worth recording, because it nearly made this module's results meaningless.

WSL shuts down its utility VM when idle. That hard-kills every qemu process, so
the guests are power-cycled and their autostart setting brings them back. The
guest boot list showed three boots in twelve minutes, and an SSH session died
mid-command. A power cut is not a normal way to run a VM, and unflushed guest
writes are at risk.

Disabled in `C:\Users\ziaur\.wslconfig`:

```ini
[wsl2]
vmIdleTimeout=-1
```

Verified rather than assumed: WSL uptime read `25s`, the shell then idled for
150 seconds with no WSL processes running, and the next read was `184s` with
both domains still up. Before the change the same idle window restarted the
distro.

Two lessons this module produced the hard way:

1. **Absence of evidence is not evidence of absence.** A dropped SSH connection
   whose stderr was sent to `/dev/null` printed nothing, which looked exactly
   like "the directory is empty". That empty-looking listing sent me chasing a
   lost-write theory for several turns before the real explanation turned up:
   the delete had worked, and every later playbook run had failed against VMs
   that were still booting, so nothing was ever redeployed. Checksums at each
   step are what settled it.
2. **A guard that can never be false is not a guard.** See the `pgrep`
   truncation bug in [host-setup.md](host-setup.md).
