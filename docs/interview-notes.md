# Interview notes

The questions this project prepares you for, with the answer grounded in
something this lab actually measured. Replace nothing with theory; every claim
below has output behind it in [`evidence/`](evidence/).

**1. Walk me through your backup verification.**
Archive the deployment, extract it into a scratch directory, hash every file in
the restore, and compare that against a manifest taken from the source. Any
difference prints `RESTORE MISMATCH` and exits non-zero, so a scheduled backup
that fails is a failed job rather than a green tick. I compare the *restore*
rather than the archive because a checksum of the archive only proves the file
did not change - it says nothing about whether the archive contains the
deployment. Evidence: `evidence/04-backup-failure-drill.txt`.

**2. Snapshot versus backup?**
A snapshot is point-in-time state on the same storage as the VM, for fast
rollback before a change. A backup is an independent, verified copy elsewhere,
for disaster recovery. A snapshot does not survive losing the disk - and I can
show that: the recovery drill destroys the VM with `--remove-all-storage` and the
snapshot dies with it. `docs/disaster-recovery.md`.

**3. What does idempotent mean, and how did you prove it?**
Running the playbook twice changes nothing the second time. The proof is the
second `PLAY RECAP`: `changed=0` on both hosts, with `ok=18` tasks on app01 -
so the tasks ran and reported nothing to do, rather than being skipped. I also
found that claim was quietly false for a while, because rebuilding an unchanged
WAR produced a different file and the deploy task reported `changed` every run;
`zip` extra metadata was the cause. `evidence/01-idempotency.txt`.

**4. A user says the site is down. What do you check?**
Apache up, then whether the proxy can reach Tomcat, then whether Tomcat is
healthy, then logs (Apache vhost logs, `journalctl -u tomcat10`), then firewall,
then disk and memory. The useful distinction: a `404` from the proxy means
Tomcat is fine and the application is missing, while a `503` means the app server
itself is unreachable. I hit both during this build. `evidence/02`.

**5. How did you find the bottleneck?**
Load-tested through the proxy while reading CPU back from Prometheus. app01 was
pinned at 100% at 1, 2 and 4 vCPUs, so the application was CPU-bound. web01 sat
at 14% and the host never passed 56%, which ruled out the proxy tier and host
saturation as explanations for the sublinear scaling - 4x the CPUs bought 2.46x
the throughput. `docs/capacity-planning.md`.

**6. How does live resize work?**
Maximums are fixed when the VM is created, and everything happens below them.
`setvcpus` past `maxvcpus` fails with `5 > 4`, and `setmem` past `maxmemory`
fails with `cannot set memory higher than max memory`. That is why
`create-vms.sh` sets `maxvcpus 4` at creation. Memory hot-added and was visible
in the guest immediately. The vCPU hot-add needed an extra step: libvirt reported
2 vCPUs, the kernel logged `ACPI: CPU1 has been hot-added`, and the CPU was left
*offline* until I onlined it, so `nproc` still said 1. `evidence/07-live-resize.txt`.

**7. How would this differ on vSphere or Hyper-V?**
Use the mapping table in the README - snapshot/checkpoint, hot-add, linked
clone/differencing disk, the NAT network versus vSwitch or port group, vMotion
versus `virsh migrate`. Be clear that the tooling used here was KVM.

**8. Why a reverse proxy in front of Tomcat?**
TLS termination, load balancing, static content, one place for access logs, and
hiding the app server. This lab makes the last one concrete: before hardening,
`curl` straight to `app01:8080` from the host returned HTTP 200, which meant the
proxy was decorative and anything on the network could bypass it. After the ufw
rules, the only way in is port 80 on web01. `docs/hardening.md`.

**9. What would you add for real high availability?**
A second app VM with Apache `mod_proxy_balancer` or HAProxy health checks, a
shared or replicated database, and a floating IP such as keepalived on the proxy
tier. Also worth naming: this lab has no HA at all, and a firewall is not
redundancy.

**10. How would you handle WebLogic or WebSphere?**
I have not used either. The concepts carry - domains and clusters, deployment,
JVM tuning, thread pools - and the admin tooling is what would need learning.

## The two questions that actually decide it

**"Tell me about something that broke."** Have three ready, because they are the
strongest material in the project:

1. A guard I wrote used `pgrep -x qemu-system-x86_64`, which can never match
   because Linux truncates process names to 15 characters. The negation was
   always true, so the "safety" check would have deleted the network bridge out
   from under running VMs. It looked correct. Only testing it against a live VM
   caught it.
2. My idempotency proof was false until I noticed that `zip` writes extra
   metadata, so rebuilding an unchanged artifact produced a different file.
3. Guests were being power-cycled between commands and my work kept vanishing. I
   ruled out the idle timeout, `systemd-oomd`, the watchdog and a daemon crash
   before noticing that kernel boot messages repeated while `boot_id` and uptime
   stayed constant - which meant the WSL kernel was alive and only the distro was
   being torn down.

**"What are the limitations?"** The README lists seven. Being able to name them
is worth more than pretending the lab is production-grade.
