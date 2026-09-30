#!/usr/bin/env bash
#
# Backs up the Tomcat deployment and then proves the backup is restorable.
#
# The pattern: archive it, restore the archive into a scratch directory, compare
# a SHA-256 manifest of the restore against the manifest of the source, and fail
# loudly on any disagreement. A backup that has never been restored is a
# hypothesis, not a backup.
#
#   tomcat-backup.sh              take a backup, and verify it as part of it
#   tomcat-backup.sh verify FILE  re-verify an existing archive
#
set -euo pipefail

SRC=/var/lib/tomcat10/webapps
DEST=/var/backups/tomcat
KEEP_DAYS=7

manifest() {
  ( cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum )
}

verify_archive() {
  local archive="$1" scratch rc=0
  scratch=$(mktemp -d)
  tar -xzf "$archive" -C "$scratch" || rc=1
  if [ "$rc" -eq 0 ] && diff <(manifest "$scratch") "${archive}.manifest" > /dev/null; then
    echo "RESTORE VERIFIED: $(wc -l < "${archive}.manifest") files match ($archive)"
  else
    echo "RESTORE MISMATCH: $archive" >&2
    rc=1
  fi
  rm -rf "$scratch"
  return "$rc"
}

if [ "${1:-}" = "verify" ]; then
  verify_archive "${2:?usage: $0 verify <archive>}"
  exit 0
fi

mkdir -p "$DEST"
chmod 750 "$DEST"
archive="$DEST/webapps-$(date +%F_%H%M%S).tar.gz"

# An empty source directory archives and "verifies" perfectly while protecting
# nothing: both manifests would be empty and the diff would pass. Fail instead.
# This is not hypothetical - an empty webapps/ after a botched test is exactly
# how a tool like this lies to you.
if [ -z "$(manifest "$SRC")" ]; then
  echo "ERROR: $SRC contains no files, refusing to write a meaningless backup" >&2
  exit 1
fi

tar -czf "$archive" -C "$SRC" .
manifest "$SRC" > "${archive}.manifest"
( cd "$DEST" && sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256" )

verify_archive "$archive"

# Retention. Deleting the .manifest and .sha256 alongside the archive is
# deliberate: an orphaned manifest is worse than none.
find "$DEST" -type f -name 'webapps-*' -mtime +"$KEEP_DAYS" -delete
echo "Backup complete: $archive ($(du -h "$archive" | cut -f1))"
