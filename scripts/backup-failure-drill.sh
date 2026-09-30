#!/usr/bin/env bash
#
# Proves the backup verification actually rejects a bad backup.
#
# Any verification tool that only ever prints success is worthless. This drill
# tampers with an archive's manifest, expects the verifier to fail with a
# non-zero exit code, then restores the manifest and expects it to pass again -
# so the tool is shown to discriminate, not to always fail.
#
#   bash scripts/backup-failure-drill.sh
#
set -euo pipefail

KEY="$HOME/.ssh/kvmlab"
HOST=192.168.122.11

ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "ops@$HOST" 'sudo bash -s' <<'REMOTE'
set -u
cd /var/backups/tomcat
A=$(ls -t webapps-*.tar.gz | head -1)
echo "Target archive: $A"
echo

cp "$A.manifest" "$A.manifest.orig"
echo "deadbeef  ./fake-file" >> "$A.manifest"
echo "--- manifest tampered, verifying ---"
set +e
/usr/local/bin/tomcat-backup.sh verify "/var/backups/tomcat/$A"
rc=$?
set -e
echo "exit code: $rc"

mv "$A.manifest.orig" "$A.manifest"
echo
echo "--- manifest restored, verifying again ---"
/usr/local/bin/tomcat-backup.sh verify "/var/backups/tomcat/$A"
echo

if [ "$rc" -ne 0 ]; then
  echo "DRILL PASSED: the tampered backup was rejected with a non-zero exit code"
else
  echo "DRILL FAILED: the tampered backup was accepted, the verification is worthless" >&2
  exit 1
fi
REMOTE
