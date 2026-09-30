# Firewall hardening

Module M8, optional in the project guide, and worth doing because it turns the
two-tier design from a diagram into an enforced fact.

## What the rules encode

The design says: the world reaches only the web tier, the web tier reaches the
application, and only the monitoring host may scrape. The rules say exactly that.

**app01 (application tier)**

| Port | Allowed from | Why |
|---|---|---|
| 22/tcp | anywhere | administration |
| 9100/tcp | `192.168.122.1` | node exporter, monitoring host only |
| 8080/tcp | `192.168.122.12` | Tomcat, web tier only |

**web01 (web tier)**

| Port | Allowed from | Why |
|---|---|---|
| 22/tcp | anywhere | administration |
| 9100/tcp | `192.168.122.1` | node exporter, monitoring host only |
| 80/tcp | anywhere | the only ingress to the application |

Both: `default deny (incoming)`.

## Ordering is the safety property

The role applies every allow rule **before** switching on the default-deny
policy:

```yaml
- name: Allow SSH
  community.general.ufw: {rule: allow, port: "22", proto: tcp}
  # ... all other allow rules ...
- name: Default deny incoming and enable
  community.general.ufw: {state: enabled, policy: deny, direction: incoming}
```

If those were reversed, the first thing an empty default-deny ruleset would kill
is the SSH session running the playbook. `ansible-playbook` does not survive
having its own connection dropped, and a lab VM that cannot be reached is a
manual console recovery. This is the cheapest possible insurance.

A snapshot (`clean-deploy`) and `virsh console` were both available as recovery
paths before the role was run, which is why it was safe to run at all.

## Verification

Each claim checked rather than asserted:

**The proxy path still works.**

```
through Apache: HTTP 200  body=OK app01
```

**Direct access to Tomcat from the host is now blocked.** This is the change
that matters, because before hardening the same request returned `HTTP 200`:

```
app01:8080 from host -> HTTP 000 (exit 28)
```

`curl` exit code 28 is a timeout, not a refusal - the firewall is dropping the
packets rather than rejecting them, which is the correct behaviour for a
default-deny policy. Confirmed from the other side too: `dmesg` on app01 showed
**10 UFW log lines** for the attempt. A blocked connection that leaves no log is
indistinguishable from a broken service.

**Monitoring was not broken by the firewall.** This is the classic self-inflicted
wound with ufw, and it is why the 9100 rule names the monitoring host explicitly:

```
192.168.122.11:9100    up
192.168.122.12:9100    up
```

**SSH is key-only.**

```
$ ssh -o PubkeyAuthentication=no ops@192.168.122.11
ops@192.168.122.11: Permission denied (publickey).
```

Password authentication was already disabled in cloud-init (`ssh_pwauth: false`),
so this confirms the setting rather than being the thing that created it.

**Idempotency survived.** The new role reports `changed=0` on the next two runs:

```
app01  : ok=18  changed=0  failed=0
web01  : ok=17  changed=0  failed=0
```

That is the full role set now - `common`, `node_exporter`, `tomcat`, `backup`,
`apache`, `hardening` - still converging to no changes.

## Why this is more than a checkbox

Before this module, `curl http://192.168.122.11:8080/labapp/health` from the host
worked, which means the reverse proxy was decorative: anything that could reach
the network could bypass Apache and talk to Tomcat directly. After it, the only
way in is port 80 on web01.

That is the actual justification for a reverse proxy tier - one ingress point,
one place for access logs, TLS termination, load balancing, and the app server
not directly reachable - and this module is where that stops being a claim in a
README and becomes something a packet cannot argue with.

## What this still does not do

Being clear about the gaps is the difference between hardening and theatre:

- **SSH is open to anywhere.** A real environment would restrict it to a bastion
  host or an admin range. Left open here deliberately so the lab stays reachable.
- **No brute-force protection.** `fail2ban` or key-only plus rate limiting would
  be the next layer; key-only auth makes the risk much smaller but not zero.
- **No TLS.** Port 80 is plaintext. The guide's stretch goal covers a
  self-signed certificate on Apache.
- **Host-level firewall, not network-level.** Real segmentation belongs in
  security groups or network ACLs, so a misconfigured host cannot open itself up.
  `ufw` is the last line, not the only one.
- **Egress is unrestricted.** Default deny applies to incoming only. Limiting
  outbound traffic is a separate project.
- **It does nothing for availability.** Firewall rules are not redundancy; a
  failed app01 is still a failed site.
