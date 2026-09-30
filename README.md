# kvm-tomcat-lab

Two-tier Java application tier on KVM virtual machines: Apache reverse proxy in
front of Tomcat 10, provisioned with idempotent Ansible.

**Status:** work in progress. This README is filled in at the end of the build
with real measured results (idempotency proof, backup/restore drill, capacity
table, recovery time).

Build log: [docs/build-log.md](docs/build-log.md)

## Target architecture

```
Host (WSL2 Ubuntu 24.04, KVM/libvirt, Prometheus, Grafana)
  |
  +-- libvirt NAT network 192.168.122.0/24
        |
        +-- web01  192.168.122.12  Apache 2.4 reverse proxy   (1 vCPU / 1 GB)
        |
        +-- app01  192.168.122.11  Tomcat 10 + labapp.war     (1-4 vCPU / 2-4 GB)
```

## Planned layout

```
kvm-tomcat-lab/
├── ansible.cfg
├── inventory.ini
├── site.yml
├── app/            tiny JSP web app + WAR build script
├── roles/          common, tomcat, apache, backup, node_exporter, hardening
├── monitoring/     Prometheus + Grafana compose stack and alert rules
├── scripts/        create-vms.sh, pull-backups.sh
└── docs/           host setup notes, screenshots, build log
```
