# 4. Doing it automatically, and protecting it

Chapters 2 and 3 built the restaurant by hand. This chapter is about the manager
with the checklist, the alarm clock, the photograph you can rewind to, and the
copy of the recipe kept at grandma's house.

## Why not just type commands like normal?

You could. Here is what happens when you do, three months later, on a second
machine:

- You forget one of the 20 steps.
- You type it slightly differently, and something behaves slightly differently.
- You cannot tell whether the machine is correct or whether you just got lucky.
- You cannot show anyone what you did.

So instead of typing commands, we describe the **result we want** in a file, and
let a tool make it true. The tool is Ansible.

## Ansible: the manager with a checklist

**What it is.** A program that logs into machines and makes them match a written
list. You write *what you want* - "Tomcat installed, this file here, this service
running" - and Ansible works out the commands.

> **Analogy.** A housekeeper with a checklist. You do not say "walk to the
> cupboard, pick up the cloth, move your arm in circles". You say "the kitchen
> should be clean". How to achieve it is their problem.

**What is in the checklist, and the vocabulary:**

| Piece | Plain meaning | Our example |
|---|---|---|
| **Playbook** | The whole checklist | `site.yml` |
| **Inventory** | The address book of machines | `inventory.ini` |
| **Role** | A group of jobs for one purpose | `tomcat`, `apache`, `backup` |
| **Task** | One line on the checklist | "Install Tomcat 10" |
| **Handler** | A job that only runs if something actually changed | "restart Apache, but only if you edited its settings" |
| **`become`** | Run as the administrator | Needed to install software |

**Why we needed it.** Two machines, dozens of settings, and a house rule that we
must be able to rebuild everything after a disaster. Typing is not an option.

**Why "the file decides the address" is a good thing.** Read our inventory:

```ini
[app]
app01 ansible_host=192.168.122.11
```

Every instruction for the kitchen is written against the name `app01`. That is why
the fixed address from Chapter 2 matters: names point at addresses, and if the
address drifted, the instructions would go nowhere.

**Where you will meet it again.** Ansible is one of the most requested skills in
operations job adverts. Its rivals are Puppet, Chef and Salt - same idea, and the
concepts move across easily. Small setups often use plain scripts instead, but the
moment there are more than a couple of machines, people reach for a tool like
this.

## Idempotent: the most important idea in the project

**What it is.** A long word for a simple property: **doing it twice is the same as
doing it once.**

> **Analogy.** A light switch, not a doorbell. Press a light switch twice and the
> light is on. Press a doorbell twice and you have rung it twice. Configuration
> should behave like the light switch.

**Why it matters so much.**

- You can run the checklist again without fear. It is always safe.
- You can run it after an interruption without unpicking what half-happened.
- You can use it to *check* a machine: run it, and if nothing changes, the
  machine is correct. That is a health check for free.
- It is the difference between "a script I ran once" and "a system I can
  manage".

**How we proved it.** We ran the playbook twice and looked at the summary:

```
PLAY RECAP
app01  : ok=18   changed=0   failed=0      <- ran 18 jobs, changed nothing
web01  : ok=17   changed=0   failed=0
```

Read that carefully, because there is a subtlety worth understanding. `ok=18` with
`changed=0` does **not** mean the jobs were skipped. It means all 18 jobs ran,
looked at the machine, and reported "this is already how you asked it to be".
`failed=0` means none of them broke.

If a job is skipped you see `skipped`, which is a different thing entirely. If a
job does something you see `changed=1`. **`changed=0` is the proof.**

**A trap we fell into.** Our proof was quietly false for a while, because one job
kept reporting `changed`: we were rebuilding the app file, and the rebuild
produced a slightly different file every time. So Ansible honestly said "this file
is different, I copied it again". The checklist was fine; the thing we handed it
was not stable. Chapter 6 has the full story.

**Where you will meet it again.** In every interview about automation, and in
every real system. The word, the idea and the proof are all expected knowledge.

## Git and GitHub: a notebook that remembers everything

**What it is.** Git keeps the entire history of a folder - every change, who made
it, and why. GitHub is a website that holds a copy of that history so others can
see it, and so you can work on it from anywhere.

> **Analogy.** A lab notebook where you cannot erase. You can write a new page
> saying "actually, yesterday's page was wrong", but yesterday's page stays there
> for anyone to read. That is a feature, not a bug.

**Why we needed it.** Three copies of safety: the project can be rebuilt from it
(which is exactly what the disaster recovery test proved), the history explains
why things are the way they are, and it is the thing a future employer looks at.

**The workflow we used, and why it looks fussy.** Every piece of work went on its
own **branch** and came back through a **pull request**:

1. Make a branch - a private copy of the work, like a rough draft.
2. Do the work, in several small saved steps (**commits**).
3. Ask for it to be added to the main version (**pull request**, or PR).
4. Look at the change one last time, then merge it in.

> **Analogy.** Nobody redraws the class poster by rubbing bits out while everyone
> watches. You draw your idea on a separate sheet, show it, and only then stick it
> on the poster.

Even working alone, this helps: the PR is a pause where you look at your own work
as a stranger would. It is also exactly how every software team works, so
practising the shape now means it is familiar later.

**A small habit worth copying.** Every commit message says what changed and *why*,
not just "update". Three months from now, "why" is the only part you will need.

## systemd timers: the alarm clock

**What it is.** Linux's built-in scheduler. You describe a job and when it should
happen, and Linux runs it for you.

> **Analogy.** An alarm clock next to a note that says "when the alarm goes off,
> make a backup".

**Why we needed it.** A backup you have to remember is not a backup. Ours runs
itself every night at 2am.

**Two units, not one.** The note (`.service`) says what to do; the alarm
(`.timer`) says when. That separation is a Linux convention.

**A detail worth understanding.** We set `Persistent=true`, which means: if the
machine was switched off when the alarm should have rung, run the job as soon as
it wakes up. Our lab machines are frequently off, so without this a night's backup
would silently not happen. **Silently not happening is the worst behaviour a
backup can have.**

**Where you will meet it again.** Timers and their older cousin **cron** are on
every Linux server. Anything that must happen regularly - backups, cleanups,
reports, certificate renewals - runs this way.

## tar and gzip: the box

**What it is.** `tar` packs many files into one file. `gzip` squeezes that file to
make it smaller. Together they make `.tar.gz`, one tidy box.

> **Analogy.** Putting the whole kitchen's recipe cards into one box, then
> vacuum-sealing the box.

**Why we needed it.** One object is far easier to copy, verify, move and store than
a folder of loose files.

**Where you will meet it again.** Constantly. Nearly every backup, download and
software package you handle is a `.tar.gz` underneath. (`.zip` is the Windows
cousin and does the same job.)

## SHA-256: the fingerprint

**What it is.** A recipe that turns any file into a short string of letters and
numbers - its fingerprint. Change one letter in the file and the fingerprint
changes completely. You cannot work backwards from the fingerprint to the file.

> **Analogy.** A fingerprint. It says *that* this is the same person, without
> telling you anything else about them. Cut your hair and the fingerprint still
> matches; change your identity and it will not.

**Why we needed it.** Fingerprints are how we answer the question "is this exactly
the same as that?", which is the heart of every check in this project. Two places
in particular:

- **Is the backup really the same as what we backed up?** Compare fingerprints.
- **Did this file survive the trip to another machine?** Compare fingerprints.

**Where you will meet it again.** Everywhere in modern computing. Downloads, code
hosting, package managers, blockchains, git itself. The name is worth
understanding: SHA-256 is one specific fingerprint recipe, and it is the common
one.

## A manifest: the list of fingerprints

**What it is.** A file listing the fingerprint of every file inside a backup.

> **Analogy.** An inventory list taped to the box, saying "inside: 5 items, and
> here is each one's fingerprint".

**Why we needed it.** Without it, a backup is a box you have never opened. With it,
you can prove the contents later, on a different machine, without having the
original to compare against.

**How we used it.** Our backup tool writes this list as it packs the box. Later
questions like "does this restore contain the right things?" become a simple
comparison of two lists.

**Where you will meet it again.** Software vendors publish checksum lists so you
can check a download. Package managers keep manifests of installed files. It is
the same trick.

## The backup that checks itself

This is the part of the project worth the most in an interview, and it is only
about 30 lines of shell script. Here is the pattern:

```
pack the folder into a box
  -> open the box into a temporary scratch folder
    -> fingerprint everything found inside
      -> compare against the list of fingerprints taken from the original
        -> different?  shout "RESTORE MISMATCH" and exit with an error
```

**Why not just fingerprint the box itself?** Because that only proves the box did
not rot while sitting on the shelf. It proves nothing about whether the box
contains your application. Opening it and comparing the contents answers the real
question: *if I unpacked this on a brand-new machine, would I get my app back?*

**Why the failure drill matters.** A checker that only ever prints "fine" is
useless. So we deliberately corrupted a backup and demanded the tool refuse it. It
did:

```
RESTORE MISMATCH: /var/backups/tomcat/webapps-...tar.gz
exit code: 1
```

Then we put it back and demanded it pass again - so we know the tool can tell the
difference, rather than always complaining.

**Where you will meet it again.** "We have backups" is a claim. "We have restored
a backup this quarter" is evidence. Employers have been burned by the first kind
of claim, so the second kind gets you hired.

## rsync: the careful mover

**What it is.** A tool for copying files between machines that only transfers what
has changed, and can pick up where it left off.

> **Analogy.** A removal van that checks which boxes are already at the new house
> and only carries the rest.

**Why we needed it.** A backup that lives only on the machine it protects is not a
backup - it dies with the machine. We copy the boxes to the host machine and
**check the fingerprints again after the journey**, because a copy that silently
went wrong is worse than no copy, since you think you are safe.

**The honest limitation.** Our copy sits on the same physical laptop. It survives
the virtual machine dying - which the disaster recovery test proved - but not the
laptop dying. Real systems send copies to a different building or to cloud
storage. Saying that out loud is part of being trustworthy about a system.

**Where you will meet it again.** rsync is one of the most-used tools in Linux
operations. Its cousins are `scp` (plain copy over SSH) and cloud storage tools.

## Snapshot versus backup: the photograph and the copy

This is the question interviewers ask most often, so learn the difference properly.

| | Snapshot | Backup |
|---|---|---|
| **Analogy** | A photograph of the room | A copy of the recipe kept at grandma's house |
| **Where it lives** | On the same disk as the machine | Somewhere else |
| **Good for** | Undoing a mistake in seconds | Surviving a disaster |
| **Survives losing the disk?** | No - it dies with it | Yes, that is the whole point |
| **Contains memory?** | Optionally yes, as ours did | No, it is a file archive |
| **Is it checked?** | Not applicable | Restored and fingerprinted |

**How we proved the difference instead of just claiming it.** In the disaster
recovery test we deleted the machine with its disk. The snapshot went too. Nothing
about the snapshot could have saved us; only the backup could.

**The snapshot drill we ran.** Take a photograph, then deliberately wreck the
kitchen, then rewind:

- Deleting the app: the site went to **404** ("the kitchen is fine, but the recipe
  is missing").
- Rewinding: **5.1 seconds**, and the app came back with the *identical*
  fingerprint.
- The clock test: the machine's uptime read "up 1 minute" before the rewind and
  "up 1 minute" after it, proving the rewind did **not** reboot the machine - it
  restored a running moment. That is why it takes five seconds instead of the
  three minutes a boot costs.

**Reading error numbers like a detective.** 404 and 503 look similar and mean
different things:

- **404** = the kitchen is alive and well, but the recipe is missing.
- **503** = the kitchen itself is not answering.

Knowing which one you are looking at saves an hour of hunting in the wrong place.
This exact distinction cost us time during the build, in Chapter 6.

## Growing a running machine (live resize)

**What it is.** Adding memory or processors to a machine that is switched **on**.
No reboot, no downtime.

> **Analogy.** Laying another table for a dinner party while the guests are
> eating, rather than asking everyone to leave and come back.

**Why we needed it.** Because it is how real capacity planning works: you measure,
then you add, then you measure again. And because the maximum you are allowed to
grow to must be set when the machine is created (Chapter 2).

**Memory worked instantly.** The machine saw the new memory immediately, with no
reboot at all: 1867 MB became 2891 MB inside the guest.

**The processor arrived but stayed asleep.** This is the best small discovery in
the project. libvirt said "you now have 2 processors". The machine still said "I
have 1". The machine's own log said:

```
ACPI: CPU1 has been hot-added
```

So the processor was delivered and plugged in - and then left switched off. The
number you check (`nproc`) counts processors that are *awake*. One extra command
to switch it on, and `nproc` said 2.

**Why this is worth telling an interviewer.** It shows the difference between
"the tool said it worked" and "I verified the thing actually works". Many people
stop at the first one.

**Where you will meet it again.** VMware calls it hot-add, Hyper-V has dynamic
memory. The same surprises happen, because they come from the same place: the
guest operating system has to notice and accept the change.
