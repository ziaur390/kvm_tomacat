#!/usr/bin/env bash
#
# Copies the backups off the VM they protect and re-verifies them here.
#
# A backup that only exists on the machine it protects is not a backup: it dies
# with that machine. This pulls the archives to the KVM host and checks the
# per-archive SHA-256 that was computed on the VM, so a transfer that silently
# corrupted the file cannot pass.
#
#   bash scripts/pull-backups.sh
#
set -euo pipefail

DEST="$HOME/kvm-lab-backups"
KEY="$HOME/.ssh/kvmlab"
SRC_HOST=192.168.122.11

mkdir -p "$DEST"
rsync -av --rsync-path="sudo rsync" -e "ssh -i $KEY" \
  "ops@$SRC_HOST:/var/backups/tomcat/" "$DEST/"

echo
echo "Verifying the archives survived the transfer:"
cd "$DEST" && sha256sum -c ./*.tar.gz.sha256
