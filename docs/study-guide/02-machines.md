# 2. Machines inside machines, and the wires between them

This chapter is about the ground floor: how you made two computers without
buying two computers, and how they talk to each other.

## A computer inside a computer (virtualization)

**What it is.** A program that pretends to be a whole computer. You give it some
of your memory, some of your disk and some of your processors, and it behaves
like a separate machine with its own operating system. You can start it, stop
it, break it, and throw it away without touching the real computer.

> **Analogy.** A folded paper house. It is a real house - you can live in it, put
> furniture in it - but it is standing inside a bigger room. Knock it down and
> the big room is fine.

**Why we needed it.** The project is about running servers. Real servers get
installed, changed, backed up and destroyed. Doing that on your own laptop
directly would be dangerous and messy. Virtual machines make it safe to
experiment.

**How we used it.** We made two virtual machines: `web01` (the waiter) and
`app01` (the kitchen).

**Where you will meet it again.** Almost everywhere. Any "cloud server" you rent
is a virtual machine. Any company server room runs hundreds of them on a handful
of big physical machines, because most servers sit idle and it is wasteful to
give each one its own hardware.

**The word for the boss program.** The thing that creates and manages virtual
machines is called a **hypervisor**. Three famous ones: **KVM** (what we used,
free, part of Linux), **VMware vSphere** (what big companies often pay for), and
**Hyper-V** (Microsoft's). They all do the same job with different buttons.

## KVM, qemu, and libvirt - three names for one job

Beginners get confused here because three programs are involved. Here is the
division of labour:

| Name | Plain meaning | In our project |
|---|---|---|
| **KVM** | The part built into Linux that lets a virtual machine use the real processor at full speed | It is a feature of the Linux kernel. We checked it was switched on. |
| **qemu** | The program that pretends to be the hardware: the disks, the network card, the screen | One `qemu` process runs for each virtual machine |
| **libvirt** | The manager. It keeps a list of machines, remembers their settings, and gives you one tidy set of commands | The `virsh` command you typed talks to libvirt |
| **virsh** | The command you type to talk to libvirt | `virsh list --all` shows your machines |
| **virt-install** | A helper that builds a new virtual machine in one command | `scripts/create-vms.sh` uses it |

> **Analogy.** KVM is the engine, qemu is the car body and wheels, libvirt is the
> garage manager who knows where all the cars are parked and what keys they need,
> and `virsh` is the clipboard you talk to the manager with.

**Why not just use qemu directly?** You can, but you would have to write a
40-line command every time and remember dozens of options. libvirt remembers for
you, and gives you useful extras like snapshots and live resizing.

**Where you will meet it again.** `virsh` skills transfer directly. If you learn
`virsh list`, `virsh start`, `virsh dominfo` and `virsh snapshot-list`, you will
recognise the same shapes in VMware (`vim-cmd`, PowerCLI) and Hyper-V
(`Get-VM`).

## Why we ran Linux inside Windows (WSL2)

**What it is.** WSL2 is Microsoft's way of running a real Linux system inside
Windows, sharing the same computer. It is not a pretend Linux; it is actual Linux
in a lightweight virtual machine that Windows starts for you.

> **Analogy.** A guest flat built into your house. Separate front door, separate
> kitchen, but the same building and the same plumbing.

**Why we needed it.** Your laptop runs Windows. KVM exists only in Linux. So we
needed a Linux machine, and instead of installing one or buying a second laptop,
WSL2 gave us one in about two minutes.

**The important trick: nested virtualization.** This means running a virtual
machine *inside* a virtual machine - our KVM machines live inside the WSL2
machine. Windows has to agree to pass the processor's virtualization feature down
the chain. It did, and we proved it:

```bash
sudo kvm-ok
# INFO: /dev/kvm exists
# KVM acceleration can be used
```

That `/dev/kvm` file is the doorway to the processor's virtualization feature. If
it is missing, virtual machines still run but in **software emulation** - the
computer pretends to be a different processor in slow motion. Everything works,
just 10 to 50 times slower.

**Honest cost.** We are running inside a wrapper, so speeds are lower and the
guest machines are capped by whatever WSL is given. The project's absolute speed
numbers describe a laptop, not a data centre. Chapter 5 says more about why that
still makes the experiment useful.

**Where you will meet it again.** WSL2 is extremely common now for developers on
Windows. On servers you would use real Linux, but every command you learned here
is the same command.

## A ready-made computer: the cloud image

**What it is.** A file containing a complete, already-installed Linux system. Not
an installer - a finished disk. You copy it and boot it, and 20 seconds later you
have a working computer with no setup questions.

> **Analogy.** A frozen meal versus cooking from scratch. Making Linux from an
> installer takes 20 minutes of clicking. The frozen version is ready in seconds,
> and you add your own salt afterwards.

**Why we needed it.** We needed to build the same machine twice - once normally,
and once again during the disaster recovery test. Doing that with an installer
would be slow and error-prone. With a cloud image it is one command.

**How we used it.** We downloaded Ubuntu's cloud image (597 MB) and **checked its
fingerprint** against the publisher's published list before using it. That
fingerprint check matters more than it looks: a corrupted or tampered base image
is a problem you would not notice for months.

**Where you will meet it again.** Every cloud provider starts from images like
this. "Amazon Machine Image" and "Azure Marketplace image" are the same idea.

## cloud-init: the note you leave for a new computer

**What it is.** A way to hand a brand-new machine a small note on first boot
saying: your name is this, make this user, here are the keys, turn off password
logins.

> **Analogy.** A note taped to the fridge in a new flat: "Your name is app01.
> The spare key belongs to Ziaur. Do not let anyone in without a key."

**Why we needed it.** A fresh cloud image has no user, no password and no way in.
Without cloud-init you would have to open a console and type everything by hand
for each machine.

**How we used it.** Our note created a user called `ops`, gave it permission to
run administrator commands without a password (so Ansible can do its job), and
installed our SSH key.

**Where you will meet it again.** Every cloud. It is *the* standard way to give a
new server its identity. On the job you will write these notes, called
`user-data` files, all the time.

## Thick disks that are secretly thin (qcow2 and backing files)

**What it is.** A disk file format that only takes up space for the data you
actually write. A "10 GB disk" may only use 700 MB on your real disk. It can also
be stacked: a small disk on top of a big read-only one.

> **Analogy.** Tracing paper. Instead of copying a whole drawing, you lay a sheet
> of tracing paper over it and only draw your changes. The original never gets
> touched, and your sheet is nearly empty.

**Why we needed it.** Two virtual machines each wanting a 10 GB disk would mean
20 GB of real space, most of it empty. With stacking, the 597 MB base is stored
**once**, and each machine has a thin layer of its own.

**How we used it.** `create-vms.sh` does exactly this:

```bash
qemu-img create -f qcow2 -F qcow2 -b noble-server-cloudimg-amd64.img app01.qcow2 10G
#                          ^^ the base image            ^^ the thin sheet on top
```

**Where you will meet it again.** VMware calls it a **linked clone**, Hyper-V
calls it a **differencing disk**, and Docker calls it a **layer**. Same idea,
three brand names. This is one of the most transferable concepts in the project.

## The ceiling you set when you build the machine

**What it is.** When you create a virtual machine you say two numbers: how much
it has now, and the maximum it is ever allowed to have.

**Why we needed it.** Because "add a processor to a running machine" only works
up to a limit fixed at creation. We wanted the machine to start small (so the
load test would find a real bottleneck) and still be able to grow later.

**How we used it.** `app01` was created with **1 processor now, maximum 4**, and
**2 GB of memory now, maximum 4 GB**. When we later tried to be greedy, the
computer said no, politely and clearly:

```
$ virsh setvcpus app01 5 --live
error: requested vcpus is greater than max allowable vcpus for the live domain: 5 > 4

$ virsh setmem app01 8G --live
error: cannot set memory higher than max memory
```

**Where you will meet it again.** VMware and Hyper-V have the same concept -
memory reservations and limits set when the machine is built. Interviewers like
this question because it shows whether you have actually done it or only read
about it.

## The wires: a private network just for the machines

**What it is.** libvirt creates a small private network for its machines:
`192.168.122.0/24`. Several things live in that one line.

> **Analogy.** A private road behind the houses. The delivery van (the internet)
> can reach the road through the gate, and the houses can talk to each other
> easily.

| Piece | Plain meaning | In our project |
|---|---|---|
| **NAT network** | Machines can reach the internet, the internet cannot reach in | Lets the machines install software |
| **Bridge** (`virbr0`) | The virtual switchboard the machines plug into | The thing that broke every time WSL restarted |
| **DHCP** | The automatic address giver | Hands out addresses when machines boot |
| **DHCP reservation** | "This machine always gets this address" | How `app01` is always `.11` |
| **Gateway** | The way out of the private road | `192.168.122.1`, the host itself |

**Why fixed addresses matter.** Ansible's address book contains two addresses. If
a machine woke up with a different one, every instruction would be sent to an
empty house. The reservation is made against the machine's **MAC address** - the
hardware's permanent serial number for its network card - so it does not matter
what order machines start in.

**Where you will meet it again.** Every network you ever touch. Subnets, NAT,
DHCP, gateways, MAC addresses - these concepts are in routers, cloud networks and
office networks alike.

## Getting in without a password (SSH keys)

**What it is.** A way to prove who you are using two matched files instead of a
typed password: a **private key** you keep secret, and a **public key** you give
away. The machine keeps a copy of your public key; if you can prove you hold the
matching private key, you are let in.

> **Analogy.** A padlock you hand out and the only key that opens it. You can
> give the padlock to a thousand people and they still cannot open it.

**Why we needed it.** Ansible logs in dozens of times per run. Typing a password
each time is impossible, and passwords can be guessed. Keys cannot reasonably be
guessed, and they let automation work.

**How we used it.** One key pair for the lab. The public half was installed by
cloud-init; password logins were switched off entirely. We then proved it:

```
$ ssh -o PubkeyAuthentication=no ops@192.168.122.11
ops@192.168.122.11: Permission denied (publickey).
```

**Where you will meet it again.** Everywhere in servers and code hosting. The
same idea is behind GitHub's push access, and behind every automated deployment
you ever write.

**The rule you must never break:** the private key file never goes into the
project folder and never into git. Our project automatically ignores files named
like keys, and we checked that no key was ever committed.
