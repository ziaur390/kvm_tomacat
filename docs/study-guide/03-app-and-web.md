# 3. The kitchen, the waiter, and the bouncer

Chapter 2 built two computers. This chapter puts food in one and a doorman on the
other.

## Java: the language the kitchen speaks

**What it is.** A programming language with one special trick: the same program
can run on Windows, Linux or a Mac without being rewritten.

> **Analogy.** Esperanto for computers. You write the recipe once, and every
> kitchen in the world can read it.

**Why it matters.** Java code does not run directly on the processor. It runs
inside a program called the **JVM** (Java Virtual Machine), which translates as it
goes. That middle layer is why Java is slower than some languages and why it works
everywhere.

**Where you will meet it again.** Enormous amounts of business software are Java:
banking, insurance, government systems. If a job mentions Tomcat, WebLogic,
WebSphere, Spring or JBoss, the language underneath is Java.

## Tomcat: the kitchen itself

**What it is.** A **web application server** for Java. It knows how to receive web
requests, find the right piece of Java code, run it, and send the answer back.

> **Analogy.** A kitchen with a rule: "Put your recipe box on this shelf and I will
> cook from it." You do not hire cooks; you hand Tomcat a box and Tomcat cooks.

**Why we needed it.** Something has to actually run our code in response to a
browser asking. Tomcat does that, plus a lot of unglamorous but essential work:
managing many visitors at once, restarting a broken app, writing logs.

**How we used it.** We installed the `tomcat10` package, and Tomcat watches one
folder: `/var/lib/tomcat10/webapps/`. Anything placed there gets picked up
automatically.

**Where you will meet it again.** Tomcat is the most common Java application
server in the world, and it is free. Its big commercial cousins are WebLogic
(Oracle) and WebSphere (IBM) - same job, more buttons, much bigger price. If you
can explain Tomcat, you can explain those in an interview.

## JSP: a web page with code inside it

**What it is.** A file that looks like a page of text but can contain small bits
of Java. Tomcat turns it into real program code the first time somebody asks for
it.

> **Analogy.** A recipe card with a note in the margin: "write today's date here".
> The card is mostly fixed text; the margin changes each time.

**How we used it.** Two tiny files:

```
health.jsp   ->  prints:  OK app01
work.jsp     ->  spends about 87 milliseconds doing heavy arithmetic, then says "done"
```

**Why the slow one?** Because of Chapter 5. To learn where a system gets stuck you
need something that genuinely works the processor hard. A page that just prints
text takes 1 millisecond and teaches you nothing. `work.jsp` was written to be
deliberately expensive, and we tuned it until one request cost about 87
milliseconds - in the range a real, slightly heavy web page might cost.

**A detail worth knowing.** The very first request to a JSP is slow, because
Tomcat has to compile it. That is why our Ansible task waits and retries instead
of expecting success immediately. If you have ever wondered why a site is slow the
first time and fast afterwards, this is often the reason.

**Where you will meet it again.** JSP is old-fashioned now - modern Java web apps
use Spring Boot with templates - but the idea (a page with placeholders filled in
by code) is everywhere. It is the same idea as PHP, or as templates in Python and
JavaScript.

## WAR: the recipe box

**What it is.** A single file containing a whole web application: pages, code,
settings, all zipped up. The name means "Web Application aRchive".

> **Analogy.** A lunchbox. Everything the kitchen needs, in one box, with the
> label on the outside.

**Why we needed it.** It gives us one object to build, one object to copy, and one
object to back up. That simplicity is the reason the whole deployment is a single
step in Chapter 4.

**How we used it.** `app/build.sh` zips three files into `labapp.war`, and the
file name decides the web address: `labapp.war` becomes the address `/labapp`.
Tomcat unpacks it into a folder of the same name.

**The little bug we found.** Building the same source twice produced two
*different* files. That sounds harmless but it broke our proof that the setup tool
changes nothing on a second run - because the tool kept seeing "a different file!"
and copying it again. The cause was extra hidden metadata that `zip` writes into
archives. One extra flag (`zip -X`) fixed it. Chapter 6 tells the full story,
because the lesson is bigger than the bug.

**Where you will meet it again.** WAR files are still how Java apps are shipped to
Tomcat, WebLogic and WebSphere. Java's newer sibling is the JAR (a plainer box),
and other languages have their own versions: a `.whl` for Python, an `.npm`
package for JavaScript. Same idea: one file, everything inside.

## Apache: the waiter at the door

**What it is.** A **web server**: the program that receives web requests first. It
is very good at the simple, high-volume work of greeting, checking, logging and
handing requests onward.

> **Analogy.** A restaurant's front-of-house staff. They do not cook, but they
> greet you, take your order, keep the guest book, and know that the kitchen is
> through the swing doors.

**Why we needed it - and not just Tomcat?** A fair question, and interviewers ask
it. Four real reasons:

1. **A single entrance.** Visitors meet one machine, not several. From outside,
   the system looks simple.
2. **Security in one place.** When you eventually add HTTPS, you configure it
   once here. The kitchen never handles certificates.
3. **One guest book.** All access records in one file, which makes investigating
   problems much easier.
4. **Growing sideways.** If you add a second kitchen later, the waiter can share
   orders between them. Tomcat alone cannot do that.

## reverse proxy: carrying the order to the kitchen

**What it is.** A rule that says "requests arriving here should quietly be handed
to that other machine over there, and the answers brought back". The visitor never
knows it happened.

> **Analogy.** A phone answering service for a small business. You dial one
> number; a friendly voice answers and passes your message to whoever actually
> does the work.

**How we used it.** Two lines inside a virtual host file - the shortest and most
important lines in the whole project:

```apache
ProxyPass        /  http://192.168.122.11:8080/
ProxyPassReverse /  http://192.168.122.11:8080/
```

Read it as: "anything asking for `/` should go to `192.168.122.11` on port `8080`".
The second line fixes up the answers on the way back so links work properly.

**A virtual host** is just a section of Apache's settings for one website. We
disabled Apache's default one so only ours is active.

**Where you will meet it again.** Every serious website does this. The same job is
done by nginx, HAProxy, and cloud load balancers. The term for the general idea is
a **load balancer** when there are several kitchens, and a **reverse proxy** when
there is one.

## The bouncer: a firewall decides who may knock

**What it is.** A list of rules about which doors are open, to whom. Anything not
allowed is ignored completely - the packets are dropped, so a visitor gets silence
rather than a refusal.

> **Analogy.** A bouncer with a guest list. Not on the list? You do not get told
> why; you simply do not get in. The door behind the building that everyone
> forgot about gets locked too - that is the part that matters.

**Why we needed it.** Before this step, the whole world (well, our little network)
could knock directly on the kitchen door and skip the waiter. That made the waiter
**decorative**. The project claimed a two-tier design, but nothing enforced it.

**How we used it.** We installed `ufw` ("uncomplicated firewall") and wrote rules
that match the design exactly:

| On `app01` (the kitchen) | Who may knock |
|---|---|
| port 22 | anyone (so we can administer it) |
| port 9100 | only the monitoring machine |
| port 8080 | only `web01` - the waiter |

| On `web01` (the waiter) | Who may knock |
|---|---|
| port 22 | anyone |
| port 9100 | only the monitoring machine |
| port 80 | anyone - the only public entrance |

**Proof it worked.** Before: knocking straight on the kitchen door returned
"Hello, here is your soup" (HTTP 200). After: nothing at all.

```
through Apache:        HTTP 200  body=OK app01
app01:8080 from host:  HTTP 000 (curl exit 28)
```

Exit code 28 means "timed out" - the packets were dropped, not refused. And we
checked the other side too: the kitchen logged 10 blocked-connection entries. **A
door that silently does not open is impossible to diagnose; a door that logs why
is a door you can fix.** That detail is worth more in an interview than the rules
themselves.

**The dangerous part.** A firewall mistake can lock you out of the machine you are
working on. Our rules are written so all the "may come in" lines happen *before*
the "everyone else is blocked" line. Reverse that order and the first thing the
firewall blocks is the connection running the job that is configuring it. We also
made sure a snapshot existed, and knew the console command to get back in, before
running it.

**Where you will meet it again.** Constantly. Cloud providers call the same thing
a **security group** or a **network ACL**, and they expect you to know which port
needs opening for which service. "Why can't the servers talk to each other" is one
of the most common problems in operations, and this is usually the answer.
