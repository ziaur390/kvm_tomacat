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
# Installed as an ExecStartPre for libvirtd.service by docs/host-setup.md.
#
# The guard is the point. If any interface is still attached to the bridge, a
# domain is live and the bridge must not be touched. An earlier version used
# `pgrep -x qemu-system-x86_64`, which can never match: Linux truncates process
# names to 15 characters, so the guard was always true and the script would have
# ripped the network out from under running VMs. Checking the bridge's own port
# list tests the actual state instead of guessing from a process name.

set -eu

BRIDGE=virbr0

[ -e "/sys/class/net/$BRIDGE" ] || exit 0

if [ -n "$(ls -A "/sys/class/net/$BRIDGE/brif" 2>/dev/null)" ]; then
  # Ports attached: a domain is using this bridge. Leave it alone.
  exit 0
fi

echo "libvirt-clear-stale-bridge: removing stale $BRIDGE"
ip link delete "$BRIDGE"
