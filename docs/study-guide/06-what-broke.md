# 6. Everything that broke, and what it teaches

This is the most valuable chapter in the guide. A project where nothing broke
teaches you almost nothing, and an interviewer knows it. Every story below is
real, in the order it happened.

Each one has the same five parts: what we saw, what we guessed, what it really
was, how we fixed it, and the lesson.

---

## Story 1: The bridge that would not come back

**What we saw.** Every time Windows' WSL restarted, the private network for our
machines refused to start:

```
error: Failed to start network default
error: internal error: Network is already in use by interface virbr0
```

**What we guessed.** A broken configuration. Maybe a wrong setting somewhere.

**What it really was.** Remember the bridge from Chapter 2 - the virtual
switchboard called `virbr0` that the machines plug into. When WSL restarts, it does
not restart the whole kernel; it restarts the *Linux user space* on top of the
same kernel. The switchboard lives in the kernel's part, so it survived. The
program that manages it (libvirt) did not. So the new manager woke up, saw a
switchboard it had not created, and refused to touch it. It was being cautious,
not broken.

**How we fixed it.** Delete the orphaned switchboard before the manager starts:

```bash
sudo ip link delete virbr0
virsh net-start default
```

Then, because it happened every single time, we made it automatic with a small
script that runs just before the manager starts.

**The lesson.** When a message says "already in use", ask *who* is using it and
*why the other thing does not know about it*. The word "already" is a clue that
something survived when it should not have. Also: this problem does not exist on a
normal Linux server, because a real reboot destroys everything together. **Knowing
that your environment has quirks, and writing them down, is part of the job.**

---

## Story 2: The guard that could never say "no"

**What we saw.** Nothing. That is what makes this story dangerous.

**What happened.** The automatic fix from Story 1 needs a safety check. It must
delete the switchboard only when *no machines are running* - otherwise it would rip
the network out from under a working machine. So we wrote:

```bash
if no qemu process is running; then delete the switchboard; fi
```

And we wrote the check as `pgrep -x qemu-system-x86_64`.

**What it really was.** Linux shortens every program's name to **15 characters**.
The program is called `qemu-system-x86_64`, which is 18. So its name is stored as
`qemu-system-x86`. Our check was looking for a name that never exists, so it
**never found anything**, so the answer to "is a machine running?" was *always*
"no". Which meant the guard was not a guard at all: it would have deleted the
network switchboard even with machines running, pulling the rug from under them.

**How we fixed it.** Ask a question whose answer cannot be wrong: *does the
switchboard have anything plugged into it?*

```bash
if the switchboard has no ports attached; then delete it; fi
```

That is the actual state of the world, not a guess based on a name.

**The lesson.** **A check that can never fail is not a check.** It looks right in
review and it is catastrophic in production, because it gives you the feeling of
safety without the substance. Also, this is why we tested it against a live
machine instead of trusting it. The most dangerous line of code in any system is
the one that decides whether to do something destructive.

---

## Story 3: It changed nothing, and it was lying

**What we saw.** Our proudest result was that running the setup tool twice changed
nothing the second time. Then we noticed the deploy job reported a change **every**
time - even when we had changed nothing at all.

**What we guessed.** A bug in Ansible. Or a file permission problem.

**What it really was.** We rebuilt the app file, and the rebuild produced a
*different file* even though the three source files were identical. The cause:
`zip` writes extra hidden information (high-precision timestamps and similar) into
archives. Different bytes meant Ansible honestly reported "this file is different,
I copied the new one".

**How we fixed it.** One extra flag tells `zip` to leave that extra information
out:

```bash
zip -q -X -r app.war .
#      ^ this one
```

Two rebuilds now produce identical fingerprints, and the second run of the setup
tool reports `changed=0` properly.

**The lesson.** **An idempotency claim is only as good as the thing you feed it.**
We had tested the tool; we had not tested whether the *input* was stable. If a
thing that should be identical is not identical, every clever check built on top of
it is meaningless. This is why the project now prints fingerprints during builds -
it turns an invisible problem into a visible one.

---

## Story 4: The backup of nothing, which verified perfectly

**What we saw.** Nothing yet. This one we caught by thinking, not by failing.

**The problem.** Our backup tool packs a folder, writes fingerprints for
everything inside, then opens the box and checks the fingerprints match. If the
folder is **empty**, then the list of fingerprints is empty, the restored list is
also empty, and the two empty lists are identical. The tool would announce:

```
RESTORE VERIFIED: 0 files match
```

A backup of nothing, reporting perfect health, every night, forever.

**Why this was not hypothetical.** During the build, our application folder really
was empty for a while. A tool without this guard would have "successfully" backed
up a week of nothing, and we would have found out during an emergency.

**How we fixed it.** Four lines at the top of the tool: if the folder has no
files, refuse to run and say why.

**The lesson.** **A checker must be able to fail, and you must have thought about
what "empty" means.** Most systems do not fail loudly; they fail *quietly and
convincingly*. Whenever you write a check, ask: what input would make this check
pass while being completely wrong?

---

## Story 5: The command that printed nothing

**What we saw.** We had deleted the application folder on purpose (as part of the
snapshot drill), but when the tool listed the folder before deleting it, the list
was **empty**. That made no sense - the app had been running seconds earlier.

**What we guessed.** Something had lost our files. We spent several turns on a
theory about data being lost during a hard shutdown, because the machines *had*
been restarting unexpectedly at the time.

**What it really was.** Boring. The connection to the machine dropped mid-command,
and we had told the command to throw away its error messages:

```bash
ssh ... "ls /var/lib/tomcat10/webapps/" 2>/dev/null
#                                       ^^^^^^^^ this
```

The error message went into the bin. All we saw was silence - and **silence looks
exactly like an empty folder**.

**How we fixed it.** Stop hiding errors on the commands that are supposed to
*prove* something. And the real fix was mental: after that, every destructive step
in the project was bracketed by fingerprint checks, so "the file is missing" could
never be confused with "the command did not run".

**The lesson.** **Never silence the error output of the command you are using as
evidence.** The first theory had been wrong, and it cost hours. The fix was not
clever: it was to make the evidence unambiguous. Two rules worth keeping forever:
do not throw away error messages, and never let "no output" count as proof.

---

## Story 6: The machines kept rebooting themselves

**What we saw.** The virtual machines rebooted every few minutes. Our work kept
vanishing. Commands failed with "no route to host". It looked like the lab was
falling apart.

**What we guessed, and ruled out one by one.** This is worth reading as a method,
because the guessing is what took the time:

- *The idle timer.* WSL switches itself off when nothing is happening. We turned
  that off and told it never to do it. **Not the cause.**
- *The memory killer.* Linux has a service that kills programs when memory runs
  out (`systemd-oomd`). Check whether it killed our virtual machines. **It was not
  even installed.**
- *The watchdog.* Each virtual machine has a "dead man's handle" device that
  reboots it if it stops responding. If it were armed, it would reboot under load.
  We checked whether anything was arming it. **Nothing was.**
- *The manager crashing.* We looked at how many times libvirt had crashed.
  **Zero times.**

**What it really was.** We finally looked at the *kernel's own log* and saw the
same boot messages repeating every few minutes:

```
Linux version 6.18.40.1-microsoft-standard-WSL2 ...
WSL (1 - mini_init): WSL user cgroup created ...
```

but at the same time, the machine's **uptime** and its **boot identity** said
"nothing has restarted". Both facts were true, and together they were the answer:
WSL keeps its kernel running, but **tears down the Linux user space as soon as the
last session closes.** Closing a session kills the virtual machine manager, which
takes the virtual machines down with it. Our machines only came back because we
had told them to start automatically.

So the "reboots" were not crashes at all. They were the lab being switched off
every time we stopped typing, and switched back on when we typed again.

**How we fixed it.** Keep a session open so WSL never decides to tear things down:

```bash
nohup wsl.exe -e bash -c "sleep 3600" >/dev/null 2>&1 &
```

Then we *verified* it: we watched the process start times and the manager's start
time, waited 90 seconds doing nothing, and looked again. Unchanged. Fixed.

**The lesson.** **"The tool said it restarted" and "the machine restarted" are
different claims.** The breakthrough came from noticing two facts that could not
both be true, and treating that contradiction as the clue instead of ignoring it.
And the method note matters too: we ruled out four plausible causes before
finding the real one, which is normal. Debugging is mostly the discipline to
eliminate without getting bored.

---

## Story 7: The processor arrived, but stayed asleep

**What we saw.** We added processors to a running machine. The manager reported
success: "2 processors". The machine itself said "I have 1".

**What we guessed.** The change had not really happened.

**What it really was.** The machine's log held the answer:

```
ACPI: CPU1 has been hot-added
```

The processor had been delivered and plugged in - and left **switched off**. The
command we were using to count processors counts the ones that are *awake*. One
extra command to switch it on, and the count was correct.

**Why nobody documented it.** Most guides check "did the tool report success?" and
stop. Success at the top does not guarantee success all the way down.

**How we fixed it.** Switch the processor on explicitly before measuring, and
document that the obvious verification step is not enough.

**The lesson.** **Verify at the place the work is used, not where it is issued.**
The manager's opinion is not evidence. The machine's own report is.

---

## Story 8: The clock that went backwards

**What we saw.** After we rewound a machine to a snapshot, its clock jumped
backwards. The machine noticed and said so in its log. About a minute later, it
restarted on its own.

**What we guessed.** Something was badly wrong - possibly the watchdog from Story
6, which would have been genuinely serious, because a watchdog firing during a
load test would silently ruin all our measurements.

**What it really was.** Rewinding to a snapshot restores a *moment*, including the
clock reading from that moment. And it invalidates anything the machine was in the
middle of doing at that moment, such as a write to disk. The machine notices both,
and can decide to restart to be safe. Not a fault - a side effect of time travel.

**How we fixed it.** Nothing to fix, but we checked the scary possibility
properly: it was not the watchdog. That mattered, because if it had been armed, it
could have restarted a machine in the middle of measuring, and we would have
published wrong numbers without knowing.

**The lesson.** **When you use time travel, expect the clock and unfinished work
to be wrong.** And: distinguish "harmless side effect" from "the same symptom
caused by something that would ruin my results". We spent a few minutes on the
second question and it was the right few minutes.

---

## The five lessons worth memorising

If you remember nothing else from this chapter:

1. **A check that can never fail is not a check.** Test your safety net by trying
   to break it, with a live system.
2. **A claim is only as good as the thing you are claiming about.** If a thing that
   should be identical is not, everything built on it is meaningless.
3. **Never silence errors on a command that is supposed to prove something.** "No
   output" is not evidence of anything.
4. **The tool saying it worked is not the same as it working.** Verify where the
   work is used.
5. **Write it down.** Every story here is in the build log with the commands and
   the output. A problem you solved and did not record is a problem you will solve
   twice.
