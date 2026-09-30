# Screenshots

Most of this project's evidence is text, in [`../evidence/`](../evidence/),
because text is greppable, diffable and regenerable. Two things need a picture.

## 1. `grafana-dashboard.png`

The Grafana **Node Exporter Full** dashboard showing both VMs.

```bash
cd monitoring && docker compose up -d
bash import-dashboard.sh
```

Then open <http://localhost:3000/d/rYdddlPWk> (`admin` / `admin`), pick a time
range that covers the load test, and capture the CPU panel for `app01`. Press
`Ctrl+Shift+E` in Grafana to render a clean PNG, which is tidier than a
screenshot of the browser.

Aim for a window that shows the CPU spike from `scripts/capacity-test.sh` - the
spike is the point, because it is what made the bottleneck visible.

## 2. `kvm-lab-terminal.png`

One terminal, two commands:

```bash
virsh list --all
virsh dominfo app01
```

That single capture covers the KVM claims: both domains running, `CPU(s): 1`
against a `Max memory` of 4 GB, which is the creation-time ceiling that makes the
live resize work. Both commands also appear as text in
[`../evidence/06-vm-shape.txt`](../evidence/06-vm-shape.txt), so the screenshot is
for the browser reader rather than being the only record.
