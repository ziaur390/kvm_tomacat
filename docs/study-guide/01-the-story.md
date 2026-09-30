# 1. The story of what we built

## Imagine a restaurant

You built a small restaurant. Not a real one - a restaurant made of software,
running inside your own laptop. Here is who works there:

| In the restaurant | In our project | What it does |
|---|---|---|
| The building | Your laptop, with WSL2 and KVM | The place everything happens |
| Two locked rooms | `web01` and `app01` | Two separate computers inside one |
| The waiter at the door | Apache on `web01` | Greets every visitor and passes orders on |
| The kitchen | Tomcat on `app01` | Actually makes the food |
| The recipe | `labapp.war` | The instructions for the food |
| The manager with a checklist | Ansible | Walks around making sure everything matches the checklist |
| A photo you can rewind to | Snapshot | Lets you undo a mistake in seconds |
| A copy of the recipe at grandma's house | Backup | Saves you if the restaurant burns down |
| The nurse with a thermometer | Prometheus | Writes down numbers every 15 seconds |
| The chart on the wall | Grafana | Draws those numbers as pictures |
| The bouncer with the guest list | Firewall (`ufw`) | Decides who is allowed through which door |

That is the whole project. Everything else is details about how those people do
their jobs.

## What a big company version looks like

Your restaurant seats 20 people. A company like a bank runs a restaurant with
5,000 tables, in three buildings, in two countries, with a second kitchen that
takes over when the first one catches fire.

The workers are the same. There are just more of them, and more rules about what
happens when something breaks. **That is why this project is worth building: the
ideas are identical, only the size changes.**

## What happens when someone visits the page

This is the single most useful thing to understand. Follow one visitor:

1. Someone opens a browser and asks for `http://192.168.122.12/labapp/health`.
2. `.12` is **web01**. The request arrives at Apache, the waiter.
3. Apache looks at its rule sheet (`labapp.conf`) which says: "anything asking
   for `/`, quietly pass it to `192.168.122.11:8080`". That is a **reverse
   proxy**: the visitor thinks they spoke to Apache, but Apache just carried
   the message to the kitchen.
4. `.11` is **app01**, and port `8080` is **Tomcat**, the kitchen.
5. Tomcat looks at the path `/labapp` and thinks "that is the app called
   `labapp`", which it found in its `webapps` folder.
6. Inside `labapp` the file `WEB-INF/web.xml` says: the address `/health` belongs
   to the file `health.jsp`.
7. Tomcat runs `health.jsp`, which prints `OK app01` - the name of the machine
   that cooked it.
8. That text travels back the same way: Tomcat to Apache, Apache to the browser.

The visitor sees `OK app01`. Notice the name says **app01**, even though they
asked **web01**. That is the proof the request really travelled between the two
machines instead of being answered at the front door.

> **Analogy.** You order soup. The waiter does not cook it, but they do hand it
> to you. If the bowl has the kitchen's stamp on it, you know the kitchen really
> made it.

## Why bother with two rooms?

A fair question. One computer could be both the waiter and the kitchen.

We split them because that is what real systems do, and each half gives you
something:

- **One front door.** Visitors only ever see `web01`. The kitchen is hidden, so
  nobody can walk in and start poking the ovens. We proved this: after
  hardening, knocking directly on the kitchen door (`app01:8080`) from outside
  gets **no answer at all**.
- **One place to add security.** When you eventually add HTTPS, you do it once,
  at the front door. The kitchen never needs to know about certificates.
- **One place to write the guest book.** Every access log is in one file on
  `web01`, instead of scattered across machines.
- **Room to grow.** If the kitchen gets busy you can add a second kitchen later
  and have the waiter share orders between them. If the waiter gets busy, add a
  second waiter.
- **Smaller blast radius.** If the front door breaks, you can still reach the
  kitchen to fix it - and the other way round.

> **Analogy.** A restaurant where customers walk straight into the kitchen is a
> food truck. Fine for one customer, chaos for a hundred.

## The order we built it in, and why that order

The build happened in nine steps, called **modules**. The order is not random.

| Step | What we did | Why it had to come in this position |
|---|---|---|
| 1 | Set up the machine that makes machines (KVM) | Nothing else exists until something can create a computer |
| 2 | Made two computers with fixed addresses | Ansible needs to know where they are, by address |
| 3 | Wrote the tiny app | The kitchen needs a recipe before it can cook |
| 4 | Told Ansible to build everything, and ran it twice | Twice is the proof it is safe to repeat |
| 5 | Took a photo (snapshot), broke things, rewound | Learn the undo button *before* you need it |
| 6 | Made a backup and restored it from scratch | Learn the ambulance before the accident |
| 7 | Put instruments on and ran a load test | You cannot tune an engine you cannot measure |
| 8 | Locked the doors | Do this last: a firewall mistake can lock you out |
| 9 | Wrote it all down | If it is not written down, it did not happen |

**Rule of thumb worth keeping:** learn the undo and the safety net before you
start breaking things on purpose. Module 5 and 6 before 8 is not an accident.

## The numbers we ended up with

Short version, because Chapter 5 explains each one:

- Running the setup tool twice in a row: the second time it changed **nothing**
  (`changed=0`). That is the proof it is safe to run again and again.
- The site answers through the front door, and the kitchen door is **closed** to
  outsiders.
- The backup was deleted, then restored from the copy kept elsewhere, and every
  fingerprint matched: **`RESTORE VERIFIED: 5 files match`**.
- Deliberately corrupting a backup made the tool **refuse** it and exit with an
  error. A checker that never complains is not a checker.
- Adding processors: **1 → 2 → 4 processors** gave **17.9 → 29.2 → 44.1
  requests per second**. Four times the cooks, 2.46 times the soup - and Chapter
  5 explains why that is a *good* result, not a disappointing one.
- The restaurant was completely destroyed (the whole computer deleted) and
  rebuilt, serving again in **5 minutes 48 seconds**.

## How to read the rest of this guide

Every subject below is explained the same four ways, so you can skip around:

- **What it is** - the plain idea, usually with an analogy.
- **Why we needed it** - the actual problem it solved *in this project*.
- **How we used it** - the concrete thing that happened here.
- **Where you will meet it again** - the real jobs and systems that use it.

Chapter 7 is a glossary and a command cheat sheet. If a word ever loses you,
jump there.
