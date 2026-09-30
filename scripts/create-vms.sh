#!/usr/bin/env bash
#
# Creates the two lab VMs from the Ubuntu noble cloud image.
#
# Idempotent: existing DHCP reservations and existing domains are skipped, so
# re-running does not destroy anything. Recreating a VM means undefining it
# first (see docs/snapshots-and-resize.md).
#
#   app01  192.168.122.11  Tomcat 10        1 vCPU / 2 GB  (max 4 vCPU / 4 GB)
#   web01  192.168.122.12  Apache 2.4        1 vCPU / 1 GB
#
# The maximums are set at creation on purpose: live CPU and memory resize in
# M5 only works up to the maximum fixed here. app01 starts at 1 vCPU so the M7
# load test has a bottleneck to find.

set -euo pipefail

PUBKEY=$(cat "$HOME/.ssh/kvmlab.pub")
IMG=/var/lib/libvirt/images/noble-server-cloudimg-amd64.img
NET=default
IMG_DIR=/var/lib/libvirt/images

reserve() { # reserve <mac> <name> <ip>
  if virsh net-dumpxml "$NET" | grep -q "mac='$1'"; then
    echo "dhcp reservation $1 -> $3 already present"
  else
    virsh net-update "$NET" add ip-dhcp-host \
      "<host mac='$1' name='$2' ip='$3'/>" --live --config
  fi
}

# Fixed addresses, so the Ansible inventory never has to change.
reserve 52:54:00:aa:00:11 app01 192.168.122.11
reserve 52:54:00:aa:00:12 web01 192.168.122.12

for vm in app01 web01; do
  cat > "/tmp/$vm-user-data" <<EOF
#cloud-config
hostname: $vm
users:
  - name: ops
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $PUBKEY
ssh_pwauth: false
EOF
done

mkvm() { # mkvm <name> <mem> <maxmem> <vcpus> <maxvcpus> <mac>
  local name=$1 mem=$2 maxmem=$3 vcpus=$4 maxvcpus=$5 mac=$6

  if virsh dominfo "$name" >/dev/null 2>&1; then
    echo "domain $name already exists, skipping"
    return 0
  fi

  # Thin overlay on the shared base image - same idea as a VMware linked clone.
  sudo qemu-img create -f qcow2 -F qcow2 -b "$IMG" "$IMG_DIR/$name.qcow2" 10G

  sudo virt-install --name "$name" \
    --memory "$mem,maxmemory=$maxmem" --vcpus "$vcpus,maxvcpus=$maxvcpus" \
    --disk "path=$IMG_DIR/$name.qcow2" \
    --os-variant ubuntu24.04 --import \
    --network "network=$NET,mac=$mac" \
    --cloud-init "user-data=/tmp/$name-user-data" \
    --noautoconsole

  # Come back automatically after a host (or WSL) restart.
  virsh autostart "$name" >/dev/null
}

#    name   mem  maxmem vcpu maxvcpu mac
mkvm app01  2048 4096   1    4       52:54:00:aa:00:11
mkvm web01  1024 1024   1    1       52:54:00:aa:00:12

echo
echo "Waiting for DHCP leases..."
sleep 20
virsh net-dhcp-leases "$NET"
