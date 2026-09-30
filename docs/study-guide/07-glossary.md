# 7. Glossary, cheat sheet, and what to learn next

## Glossary, in plain words

**Ansible** - A program that reads a written checklist and makes machines match
it. The manager with the clipboard.

**Apache** - The waiter. The web server that greets requests first and passes them
to the kitchen.

**ab** - ApacheBench. A program that pretends to be many visitors at once, to see
how a system behaves under pressure.

**backing file** - The big read-only disk that thin disks are layered on top of,
like tracing paper over a drawing.

**backup** - An independent copy kept somewhere else, which is checked. The copy of
the recipe at grandma's house.

**bridge (`virbr0`)** - The virtual switchboard that virtual machines plug into.

**capacity planning** - Deciding how big a system should be by measuring it, rather
than guessing.

**checksum / fingerprint (SHA-256)** - A short string computed from a file. Change
one letter and it changes completely. Used to answer "is this the same as that?"

**cloud image** - A finished, pre-installed operating system in a file. A frozen
meal instead of cooking from scratch.

**cloud-init** - The note you leave for a brand-new machine telling it who it is and
how to let you in.

**commit** - One saved step in the history of a project, with a message about why.

**container (Docker)** - A program sealed together with everything it needs, so it
runs the same anywhere. A shipping container.

**cron / timer** - The alarm clock that runs jobs on a schedule.

**DHCP** - The automatic address giver on a network.

**DHCP reservation** - "This machine always gets this address", matched by the
machine's hardware serial number.

**emulation** - Pretending to be a different processor, in slow motion. What
happens when hardware virtualization is unavailable.

**firewall (`ufw`)** - The bouncer with the guest list. Decides which doors are
open to whom.

**Grafana** - The chart on the wall. Draws monitoring numbers as pictures.

**guest** - A virtual machine, from the point of view of the host.

**handler** - An Ansible job that only runs if something actually changed. "Restart
the service, but only if you edited its settings."

**host** - The real machine that runs virtual machines; or, the thing a container
runs on.

**hot-add / live resize** - Adding memory or processors to a machine that is
switched on.

**hypervisor** - The boss program that creates and manages virtual machines. KVM,
VMware, Hyper-V.

**idempotent** - Doing it twice has the same result as doing it once. A light
switch, not a doorbell.

**inventory** - Ansible's address book of machines.

**JAR / WAR** - The sealed box containing a Java program (`.jar`) or a whole Java
web application (`.war`).

**Java / JVM** - The language and the program that runs it. The Esperanto of
programming languages.

**JSP** - A web page with small pieces of Java code inside it.

**KVM** - The virtualization feature built into Linux. The engine.

**libvirt** - The manager that remembers virtual machines and gives you tidy
commands for them. Talked to with `virsh`.

**manifest** - A list of the fingerprints of every file in a backup. The inventory
list taped to the box.

**metric** - A number with a timestamp. A row in the nurse's notebook.

**NAT** - A private network that can reach out to the internet, while the internet
cannot reach in.

**node_exporter** - The little meter on each machine that reports how busy it is.

**p95 latency** - The time 95 out of 100 requests took. Finds the slow ones that an
average would hide.

**playbook** - The whole checklist in Ansible (`site.yml`).

**Prometheus** - The nurse with the notebook. Collects and stores monitoring
numbers, and checks alert rules.

**PromQL** - The little language for asking questions of monitoring numbers.

**pull request (PR)** - A polite request to add your work to the main version, with
a chance to look at it first.

**qcow2** - The disk file format that only uses space for data you actually write,
and can be layered on a base image.

**qemu** - The program that pretends to be the hardware of a virtual machine. The
car body and wheels.

**reverse proxy** - A rule that quietly hands requests to another machine and
brings the answers back. A phone answering service.

**role** - A group of Ansible jobs for one purpose, such as `tomcat`.

**rsync** - The careful mover that copies only what changed and can be interrupted.

**scrape** - Prometheus fetching numbers from a machine on a timer.

**snapshot** - A photograph of a machine at one moment, stored on the same disk.
For fast undo, not for disasters.

**SSH key** - A padlock you hand out and the only key that opens it. Replaces
passwords.

**systemd** - The part of Linux that starts and supervises programs.

**task** - One line on the Ansible checklist.

**throughput** - How much work is finished per second. Bowls of soup per minute.

**Tomcat** - The kitchen. A Java web application server.

**virtual host** - A section of a web server's settings for one website.

**virtualization** - Making a computer inside a computer. A folded paper house
inside a bigger room.

**virsh** - The command you type to talk to libvirt. Talking to the garage manager.

**WSL2** - Microsoft's way of running real Linux inside Windows. A guest flat built
into your house.

## Command cheat sheet

**Machines**

```bash
virsh list --all                    # list machines and whether they are running
virsh dominfo app01                 # full detail: processors, memory, state
virsh start app01 / shutdown app01  # switch on / ask politely to switch off
virsh destroy app01                 # pull the plug (use with care)
virsh console app01                 # look at its screen (leave with Ctrl + ])
virsh net-list --all                # is the private network up?
virsh net-dhcp-leases default       # which machine has which address
virsh domblklist app01              # which disk file is it using
virsh autostart app01               # start it automatically when the host boots
```

**Snapshots and resizing**

```bash
virsh snapshot-create-as app01 my-photo --description "..."
virsh snapshot-list app01
virsh snapshot-revert app01 my-photo
virsh setvcpus app01 2 --live       # add processors while running
virsh setmem  app01 3G --live       # add memory while running
# inside the machine, switch a new processor on:
echo 1 | sudo tee /sys/devices/system/cpu/cpu1/online
```

**Automation**

```bash
ansible all -m ping                 # can I reach every machine?
ansible-playbook site.yml            # make the machines match the checklist
ansible-playbook site.yml --limit app  # only the kitchen machine
```

**The application**

```bash
bash app/build.sh                                     # build the WAR
curl http://192.168.122.12/labapp/health              # through the waiter
curl http://192.168.122.11:8080/labapp/health         # straight to the kitchen (blocked)
ssh -i ~/.ssh/kvmlab ops@192.168.122.11               # log in to the kitchen
sudo journalctl -u tomcat10 -n 50 --no-pager          # the kitchen's diary
```

**Backups**

```bash
sudo systemctl start tomcat-backup.service            # make a backup now
sudo journalctl -u tomcat-backup.service -n 20        # did it verify?
systemctl list-timers tomcat-backup.timer             # when does it run next?
sudo /usr/local/bin/tomcat-backup.sh verify <archive> # check one by hand
bash scripts/pull-backups.sh                          # copy them off the machine
bash scripts/backup-failure-drill.sh                  # prove the checker works
```

**Monitoring**

```bash
cd monitoring && docker compose up -d                 # start Prometheus + Grafana
docker compose logs --tail 20                         # what are they saying?
curl -s localhost:9090/api/v1/targets                 # are the machines reporting?
curl -s localhost:3000/api/health                     # is Grafana alive?
```

**Measuring and evidence**

```bash
bash scripts/capacity-test.sh                         # the load test sweep
bash scripts/capture-evidence.sh                      # regenerate the evidence
ab -n 2000 -c 20 http://192.168.122.12/labapp/work    # one load test by hand
```

**The lab's two house rules**

```bash
# 1. Before a session, keep a WSL session open so the machines are not
#    switched off between commands:
nohup wsl.exe -e bash -c "sleep 3600" >/dev/null 2>&1 &

# 2. After any WSL restart, check the network came back:
virsh net-list --all && ping -c1 192.168.122.1
```

## Where you will meet all of this again

| If the job says... | This project covers... |
|---|---|
| VMware / Hyper-V / KVM | Chapters 2 and 4: machines, snapshots, hot-add, the mapping table |
| Linux administration | Every chapter: systemd, users, permissions, logs, SSH |
| Ansible / configuration management | Chapter 4: roles, idempotency, and proof of it |
| Tomcat / WebLogic / Apache / nginx | Chapter 3: app servers, reverse proxies, virtual hosts |
| Shell scripting | The backup tool, the VM builder, the load test - all shell |
| Backup, DR, restore testing | Chapter 4 and the disaster recovery drill |
| Monitoring, Prometheus, Grafana | Chapter 5 |
| Capacity planning | Chapter 5: the whole experiment |
| Networking, firewalls | Chapters 2 and 3 |
| Containers, Docker | Chapter 5 |
| Git, code review, CI | Chapter 4: branches, pull requests, clean history |

## Sentences worth being able to say out loud

Short versions you can say in an interview without rambling:

- **Idempotency:** "Running the playbook twice reports `changed=0` on the second
  run, which means every task inspected the machine and found nothing to do. To
  keep that true I had to make sure my build produced identical files, because a
  rebuild that changes bytes makes the deploy task report a change forever."
- **Snapshot versus backup:** "A snapshot lives on the same disk as the machine, so
  it is for fast rollback. A backup is an independent, verified copy elsewhere, for
  disaster recovery. I proved the difference by destroying the machine - the
  snapshot died with the disk, and the backup brought the application back."
- **Backup verification:** "I restore the archive into a scratch directory and
  compare checksums against a manifest from the source, so I am verifying the
  restore rather than trusting the archive. I also tamper with a manifest and
  confirm the checker refuses it, because a checker that only ever passes is
  worthless."
- **Capacity:** "I load-tested through the proxy and read CPU back from Prometheus.
  The app VM was pinned at 100% at every size, the proxy sat at 14% and the host
  never passed 56%, so the app was the bottleneck and neither the proxy tier nor
  host exhaustion explained the flattening."
- **Honesty about measurement:** "The same experiment run twice differed by about
  20%, which is systematic rather than noise, so I quote the shape of the result
  rather than the exact numbers."
- **Something that broke:** "My safety guard used `pgrep -x qemu-system-x86_64`,
  which can never match because Linux truncates process names to 15 characters. So
  the guard was always true and would have deleted the network bridge out from
  under running machines. It looked correct in review; only testing it against a
  live machine caught it."

## What to learn next, in a sensible order

1. **The same lab, automated one level higher.** Terraform can create the virtual
   machines themselves, instead of a shell script. Same idea as Ansible but for
   *machines* rather than *settings inside machines*.
2. **Automatic checks on every change.** GitHub Actions running `ansible-lint` and
   `yamllint` when you push. That is the beginning of CI.
3. **A second kitchen and a load balancer.** Add a second app machine and let
   Apache share orders between them, then switch one off and show that no requests
   fail. That is the beginning of high availability.
4. **HTTPS.** A self-signed certificate on Apache. It teaches how TLS actually
   works, and it is the first thing a security reviewer asks about.
5. **Containerise the application itself.** Build a Docker image that contains
   Tomcat and the WAR, so the app can be started anywhere in one command.
6. **Kubernetes.** The moment you have more than a couple of containers, people
   reach for it. It is a big subject; learn it after you have done steps 1 to 5.
7. **Something with a database.** Add a real database, and the backup conversation
   becomes genuinely interesting, because a database cannot just be copied while
   it is running.

## The one-page summary

You built two computers inside your computer. One is a waiter that greets
visitors, one is a kitchen that makes the food. You wrote a checklist so a
program could build both machines identically, and proved it was safe to run
twice. You took a photograph so you could undo mistakes in seconds, and you kept
a copy of the recipe somewhere else so you could survive a disaster - then proved
it by destroying the kitchen entirely and rebuilding it in under six minutes. You
put meters on both machines, drew the numbers on a wall, and used them to find out
exactly which part was the slow one. Then you locked the doors so visitors could
only come through the front.

**The part that will get you hired is not that it worked.** It is that you can say
what broke, why it broke, how you found out, and what you would do differently -
because that is the job.
