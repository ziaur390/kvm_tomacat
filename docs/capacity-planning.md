# Monitoring and capacity planning

Module M7. This is the module that produces numbers worth talking about in an
interview, so the interesting part is not the table. It is what the table rules
out.

## Monitoring stack

`docker compose up -d` in `monitoring/` starts Prometheus 3.15.0 and Grafana
13.2.3, both pinned and both with `network_mode: host`.

Host networking is required rather than cosmetic: Prometheus has to reach the VMs
on `192.168.122.0/24`, which is libvirt's NAT network inside this distro's
network namespace. Verified rather than assumed:

```
$ docker run --rm --network host curlimages/curl:latest \
    -s -o /dev/null -w "%{http_code}\n" http://192.168.122.11:9100/metrics
200
```

Both targets come up:

```
192.168.122.11:9100   job=node   health=up
192.168.122.12:9100   job=node   health=up
```

Four alert rules load and evaluate: `InstanceDown`, `HighCPU`, `LowDisk`,
`LowMemory`.

The Grafana datasource is **provisioned from the repo**
(`monitoring/grafana/provisioning/`), not clicked into the UI, and the Node
Exporter Full dashboard (grafana.com ID 1860) is imported by
`monitoring/import-dashboard.sh` through the Grafana API. Nothing in this
project depends on someone remembering to click something.

```
$ bash monitoring/import-dashboard.sh
Downloading dashboard 1860 from grafana.com...
  468600 bytes
Importing into http://localhost:3000...
{"uid":"rYdddlPWk","title":"Node Exporter Full","imported":true}
```

## Tuning the workload first

The original `work.jsp` loop of 3,000,000 iterations cost **196 ms** per request
on a 1 vCPU app01 - slower than the 50-100 ms the load test needs, which would
have made the server collapse at low concurrency instead of saturating a CPU.
Measured, then changed:

```
3,000,000 iterations -> 196.0 ms/request
1,000,000 iterations ->  86.8 ms/request
```

## The experiment

`scripts/capacity-test.sh` hot-adds vCPUs, onlines them inside the guest, runs
`ab -n 2000 -c 20` against `/labapp/work` through Apache, and reads peak CPU back
from Prometheus. Hot-add works because `create-vms.sh` set `maxvcpus 4` at
creation, and the guest has to be told to online the new CPUs (M5).

| app01 vCPUs | guest `nproc` | req/sec | p95 | app01 CPU | web01 CPU | host CPU |
|---|---|---|---|---|---|---|
| 1 | 1 | 17.93 | 1497 ms | 100% | 14% | 16% |
| 2 | 2 | 29.18 | 971 ms | 100% | 14% | 31% |
| 4 | 4 | 44.14 | 761 ms | 100% | 14% | 56% |

Throughput: 1 → 2 vCPUs is a 1.63x gain, 2 → 4 is a further 1.51x. So 4x the
CPUs bought 2.46x the throughput, and p95 latency improved 2.0x.

## What the table actually rules out

This is the part worth saying out loud, because it is what separates a measured
result from a guess:

- **app01 is the bottleneck, and it is confirmed at every size.** Its CPU is
  pinned at 100% in all three runs. The application really is CPU-bound.
- **The reverse proxy is not the constraint.** web01 sits at 14% regardless of
  load. A 1 vCPU Apache was never close to being the limit, so the 44 req/sec is
  not an artefact of the proxy tier.
- **The host is not exhausted.** Host CPU rises 16% → 31% → 56% and never
  approaches saturation, so the flattening is not caused by running out of host
  CPU, and `ab` is not the limit either.
- **The host is 4 physical cores with SMT.** An i5-1155G7 reports 4 cores and 8
  logical processors, and WSL sees 8 CPUs. At 4 vCPUs, app01 occupies every
  physical core - sharing them with the load generator, Apache on web01,
  Prometheus, Grafana and the host itself. Sibling hyperthreads share execution
  units and L3, which is a good explanation for the 3rd and 4th vCPU adding less
  than the 1st and 2nd.

**What the data does not prove.** It cannot separate shared-core contention from
the JVM's own serial parts (GC, single-threaded components). Both would produce
the same sublinear curve. Telling them apart needs the JMX exporter from the
stretch goals, which is exactly what it is for.

## Honesty about the numbers

The same experiment was run twice. The first pass, before the CPU readback was
fixed, gave 14.71 / 23.88 / 36.65 req/sec; the second gave 17.93 / 29.18 / 44.14.
That is a consistent ~20% offset across all three data points, which points at a
systematic difference between the runs (JIT warmth, background load) rather than
random noise.

So: the **shape** of the result - app01 pinned at 100%, throughput scaling
sublinearly, host never saturated - reproduced in both runs and is the finding.
The absolute requests per second are indicative, not precise, and the README says
so. Quoting 44.14 req/sec as though it were exact would be dishonest.

## Background load, checked rather than assumed

`docker ps` revealed three containers from another compose project on this host
(`server-operations-lab-api-1`, `-nginx-1`, `-db-1`), running throughout the
experiment. Measured rather than hand-waved:

```
NAME                            CPU %     MEM USAGE
server-operations-lab-api-1     0.21%     39.09MiB
server-operations-lab-nginx-1   0.00%     6.84MiB
server-operations-lab-db-1      0.00%     19.28MiB
```

Effectively idle, so they did not distort these results. Worth recording anyway,
because "the numbers looked fine so the environment must have been clean" is how
capacity tests go wrong.

## What I would do next

- Move the load generator off the host. `ab` shares 4 physical cores with the
  thing it is measuring, which caps how much the vCPU count can help.
- Give web01 more than 1 vCPU so the proxy tier is excluded at higher load
  rather than merely observed to be low at this load.
- Add the JMX exporter to separate JVM GC behaviour from raw CPU saturation.
- Run a longer test with a mixed workload (`/health` and `/work`) to see whether
  the ceiling is per-request CPU or connection handling.

## Limitations

Single host, single app VM, no HA. The absolute numbers describe a laptop CPU
running nested virtualisation, not a data centre. They are useful for
demonstrating the method and the shape of the scaling curve, not for sizing real
hardware.
