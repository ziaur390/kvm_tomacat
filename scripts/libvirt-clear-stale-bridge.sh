#!/bin/sh
#
# Delete a stale libvirt bridge left behind by a WSL restart.
#
# WSL restarts only the distro's init, not the VM kernel, so libvirt's virbr0
# bridge can outlive libvirtd. The new libvirtd then refuses to start the
# network:
#
#   error: internal error: Network is already in use by interface virbr0
#
# On a real Ubuntu host this never happens, because a reboot destroys the whole
# network namespace along with the bridge.
#
# Safe to run at any time: it only touches the bridge when it exists AND no qemu
# domain is running, so an ordinary `systemctl restart libvirtd` with live VMs
# does not lose its network. Installed as an ExecStartPre for libvirtd.service
# by docs/host-setup.md.

set -eu

if ip link show virbr0 >/dev/null 2>&1 && ! pgrep -x qemu-system-x86_64 >/dev/null 2>&1; then
  echo "libvirt-clear-stale-bridge: removing stale virbr0"
  ip link delete virbr0
fi
