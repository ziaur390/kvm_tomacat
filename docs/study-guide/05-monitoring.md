# 5. Watching, measuring, and finding the slow part

Chapter 4 protected the restaurant. This chapter puts instruments on it and works
out where the queue forms.

## Why measure at all?

**What it is.** Writing down numbers about a system over time, so you can answer
questions instead of arguing about opinions.

> **Analogy.** A thermometer and a chart on the kitchen wall. Without them, "the
> kitchen feels slow today" is the best anyone can say. With them, you can see
> that the kitchen hits its limit every day at noon, and does nothing about it for
> the other 23 hours.

**Why we needed it.** Three jobs:

1. **To see problems before people complain.** "Is the machine about to fill its
   disk?" is answerable in advance.
2. **To find the slow part.** Guessing where a system is stuck is usually wrong.
3. **To prove a change helped.** We added processors and could show exactly what
   it bought us, in numbers.

**Where you will meet it again.** Every operations job. The general term is
**observability**, and it splits into three related ideas worth knowing by name:
**metrics** (numbers over time), **logs** (things that happened), and **traces**
(the path one request took through a system).

## Prometheus: the nurse with the notebook

**What it is.** A program that asks every machine "how are you?" every few
seconds, writes down the answers with a timestamp, and lets you ask questions
about the history.

> **Analogy.** A nurse who walks the ward every 15 seconds and writes down
> everyone's temperature. Nobody has to be watched; the notebook fills itself.

**Why we needed it.** Somebody has to collect the numbers, and importantly, keep
them. A number you looked at once is forgotten. A number written down every 15
seconds lets you see that the processor has been busy since 9am.

**Two words worth knowing.** Each machine "answers questions" at a web address -
ours at port `9100`. Prometheus **scrapes** that address, which simply means it
fetches the numbers on a timer.

**Where you will meet it again.** Prometheus is the standard free monitoring
system. Its hosted cousins are Datadog, New Relic and Grafana Cloud. The words
"scrape", "metric" and "alert rule" transfer directly.

## node_exporter: the little meter on each machine

**What it is.** A small program installed on a machine that reports basic facts
about it: how busy the processor is, how much memory is free, how full the disk
is, how much network traffic there has been.

> **Analogy.** A meter reader for a house. It does not fix anything; it just knows
> how much electricity is being used and tells anyone who asks.

**Why we needed it.** Prometheus cannot see inside a machine by itself. It needs
something inside to report. That is all `node_exporter` is.

**A useful detail.** It is not part of the operating system; it is just a program.
If it stops, monitoring of that machine stops - so one of our alert rules is
literally "this machine has stopped answering".

**Where you will meet it again.** Almost every Linux server being monitored has
one of these installed. The pattern (a small agent reporting local facts) repeats
everywhere: container agents, database exporters, application exporters.

## A metric: a number with a timestamp

**What it is.** The basic unit of monitoring: a number, a name, and the time it
was taken.

> **Analogy.** A row in the nurse's notebook: "3:15pm - Mr Patel - 37.1".

**Why it matters that numbers come with timestamps.** Because a single number is
almost meaningless and a series of them is a story. "Processor at 100%" is scary.
"Processor at 100% for two minutes and then back to 5%" is a build job. The
history is the information.

**PromQL** is the little language for asking questions of these numbers. Our whole
alerting setup uses expressions a person can read aloud, for example:

```
100 - (average idle processor percentage)  >  80
```

That reads as: "if the machine has been more than 80% busy for two minutes, tell
me". The "for two minutes" part matters - a brief spike is normal, so rules wait
before shouting. Learning to write that short delay is the difference between
alerting that people trust and alerting that people ignore.

**Where you will meet it again.** Every monitoring system has a query language.
Learning one teaches you the shape of them all.

## Alert rules: the rules that decide when to say something

**What it is.** Small statements that turn numbers into meanings: "if this, for
this long, then that is a problem".

> **Analogy.** A smoke alarm. Not a fire - a *rule about* fires, so nobody has to
> sit and watch.

**Why we needed them.** Nobody watches a chart for a living. Rules watch the chart
and only bother a human when something is genuinely wrong.

**How we used them.** Four rules, all readable at a glance:

| Rule | Written as | Plain meaning |
|---|---|---|
| InstanceDown | `up == 0` for 1 minute | A machine has stopped answering |
| HighCPU | processor over 80% for 2 minutes | Something is working very hard |
| LowDisk | less than 15% of the disk free | The disk is filling up |
| LowMemory | less than 10% memory available | Memory is nearly used up |

**Note which ones are *not* about the current moment.** A processor spike is not
news. A processor that has been flat out for two minutes is. Good alerts describe
a trend, not an instant.

**Where you will meet it again.** Every system that pages someone at 3am has rules
like these. Writing alerts that do *not* cry wolf is a skill in itself, and
"alert fatigue" - where people ignore alerts because there are too many - is a
well-known problem.

## Grafana: the chart on the wall

**What it is.** A program that draws Prometheus's numbers as pictures, and lets you
arrange those pictures on a page.

> **Analogy.** The nurse has the notebook; Grafana draws the chart on the wall so
> everyone can see at a glance how the ward is doing.

**Why we needed it.** Numbers in a table are slow to read. A line going up is
instant. Pictures are also how you explain a system to someone else in a meeting.

**A dashboard** is just a page full of charts. We used a well-known ready-made one
called "Node Exporter Full" (number 1860 on grafana.com), which draws everything
about a Linux machine - processors, memory, disk, network - without us designing
it.

**One thing we did differently from most tutorials.** Rather than clicking in the
web page to connect Grafana to Prometheus, we put the settings in a file in the
project. So when someone downloads this project, the charts are already connected
- nothing depends on a person remembering to click. **Making setup automatic
instead of "here are the steps, don't forget them" is worth more than it sounds,
and interviewers notice it.**

**Where you will meet it again.** Grafana is extremely common for dashboards in
every industry. Being able to build a useful dashboard - not a pretty one, a
*useful* one - is a genuinely valuable skill.

## Docker: shipping containers for software

**What it is.** A way to run a program together with everything it needs, sealed
inside a standard box, so it works the same on any machine. Running several such
boxes together is arranged with a file called `docker-compose.yml`.

> **Analogy.** Shipping containers. It does not matter what is inside, the same
> crane can lift it and the same ship can carry it.

**Why we needed it here.** Prometheus and Grafana are two programs with their own
requirements. Using containers meant two lines of setup instead of two software
installations.

**A networking detail that mattered.** Containers normally live in their own little
network and cannot see the virtual machines. We used a setting called **host
networking** to put them on the same network as the machines, and then *checked*
it worked before trusting it, by asking a container to fetch a page from one
machine. Assumptions in networking are how afternoons disappear.

**Where you will meet it again.** Everywhere, and probably in your next job. The
ideas to learn next after this project are how containers store data, and
Kubernetes, which is the tool for running many containers across many machines.

## ab: pretending to be a crowd

**What it is.** A small program that sends many web requests at once, to see how
the system behaves under pressure. The name means ApacheBench.

> **Analogy.** Hiring 20 people to call the restaurant at the same moment, to find
> out whether one waiter is enough.

**Why we needed it.** "Is this fast?" is not answerable by clicking a page once.
You need many visitors at the same time, repeatedly, with numbers recorded.

**The command, and what it means:**

```bash
ab -n 2000 -c 20 http://192.168.122.12/labapp/work
```

- `-n 2000` means "send 2000 requests in total".
- `-c 20` means "20 of them at the same time".
- The address is the deliberately expensive page from Chapter 3, because we want
  the system to work hard, not idle.

**Where you will meet it again.** Load testing is standard practice before a big
launch. ab's more powerful relatives are `wrk`, `hey`, JMeter and k6.

## The two numbers that matter: throughput and p95

**Throughput** (also "requests per second") is how much work the system finishes
per second.

> **Analogy.** How many bowls of soup the kitchen serves per minute.

**p95 latency** is the time 95 out of every 100 requests took. Not the average -
the *slow* ones.

> **Analogy.** The average waiting time might be one minute, but if one guest in
> twenty waits fifteen minutes, that guest is writing an angry review. The average
> hides them; p95 finds them.

**Why p95 instead of the average.** Averages let a few terrible results hide behind
lots of quick ones. Real users experience the slow ones. This is why real teams
watch p95 and p99, and saying so in an interview marks you as someone who has
actually looked at a dashboard rather than just read about one.

## What we found, and why the answer was interesting

We measured the system with 1, then 2, then 4 processors on the kitchen machine:

| Kitchen processors | requests/sec | p95 | kitchen CPU | waiter CPU | whole laptop CPU |
|---|---|---|---|---|---|
| 1 | 17.93 | 1497 ms | 100% | 14% | 16% |
| 2 | 29.18 | 971 ms | 100% | 14% | 31% |
| 4 | 44.14 | 761 ms | 100% | 14% | 56% |

**The disappointing-looking headline:** four times the processors gave only 2.46
times the soup. Not four times.

**Why that is actually the *good* result.** Because of what the numbers rule out:

- The kitchen is pinned at **100%** every single time. So the kitchen really is
  the thing holding everything back. Good - we found it.
- The waiter stays at **14%**. So the front door is not the problem, and 44 soups
  per second is not an artefact of the waiter being slow.
- The whole laptop never goes above **56%**. So we did not "run out of computer",
  and the crowd-generating program was not itself the limit.
- The laptop has **4 real processor cores**, each pretending to be two. At 4
  processors, the kitchen is using every real core - and sharing them with the
  waiter, the nurse (Prometheus), the chart (Grafana) and the crowd itself.
  Sharing a core with someone else slows you down, and that is why the third and
  fourth processor add less than the first and second.

**What we genuinely could not tell apart.** Whether the flattening is caused by
core sharing, or by the Java program's own internal bottlenecks (some parts of a
program simply cannot be parallelised). Both produce exactly the same shape of
curve. Saying "I cannot separate those two with the data I have" is a stronger
answer than inventing a reason.

**Being honest about the numbers.** We ran the experiment twice and got 14.71 /
23.88 / 36.65 the first time and 17.93 / 29.18 / 44.14 the second. That is a
consistent 20% difference across all three points - which means something
systematically changed between runs, rather than random wobble. So the *shape* is
the finding, and the exact numbers are approximate. **Quoting 44.14 as if it were
precise would be dishonest, and honesty about measurement is a professional
skill, not a weakness.**

## Capacity planning: how many cooks do we need?

**What it is.** Using measurements to decide how big a system should be, instead
of guessing.

> **Analogy.** Deciding how many tables to put in a restaurant by counting how many
> guests actually arrive, rather than by what feels about right.

**The idea in three steps**, which is really the takeaway from this whole chapter:

1. **Measure** the system as it is now. (One cook: 17.9 soups per second.)
2. **Change one thing** and measure again. (Two cooks: 29.2. Four: 44.1.)
3. **Find the limit.** Where does adding more stop helping, and what runs out
   first?

**Why step 3 is the valuable one.** Adding cooks forever is expensive, and past a
point it does nothing at all. Knowing *where* the ceiling is - and being able to
say why - is what separates "I ran a load test" from "I did capacity planning".

**Where you will meet it again.** Every company that pays for computers. Cloud
bills are directly tied to how big you make things, and being the person who can
say "we need this size, and here is the measurement" is genuinely valuable to an
employer.
