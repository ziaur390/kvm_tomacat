# Backup with a verified restore

Module M6. The claim this module makes is not "there is a backup". It is "the
backup has been restored and the restore matches, and I can prove the checker
rejects a bad one".

## The pattern

```
archive the source
  -> extract the archive into a scratch directory
    -> hash every file in the extracted copy
      -> compare against the manifest taken from the source
        -> mismatch: print RESTORE MISMATCH and exit non-zero
```

`roles/backup/files/tomcat-backup.sh` does exactly this, and
`scripts/backup-failure-drill.sh` proves the failure path works.

## Why compare a restore instead of just checksumming the archive

Checksumming the archive only proves the file did not change while it sat there.
It says nothing about whether the archive actually contains the deployment it
claims to contain, and nothing about whether it is complete.

Comparing a restored tree against the source manifest answers the real question:
*if I unpacked this on a bare machine, would I get the same bytes back?* That is
the only property that matters at 3am.

## Result on a real run

```bash
ssh ops@192.168.122.11 'sudo systemctl start tomcat-backup.service'
ssh ops@192.168.122.11 'sudo journalctl -u tomcat-backup.service -n 12 --no-pager'
```

```
RESTORE VERIFIED: 5 files match (/var/backups/tomcat/webapps-2026-09-30_124302.tar.gz)
Backup complete: /var/backups/tomcat/webapps-2026-09-30_124302.tar.gz (4.0K)
```

```
$ sudo ls -la /var/backups/tomcat/
-rw-r--r-- 1 root root 1327 webapps-2026-09-30_124302.tar.gz
-rw-r--r-- 1 root root  436 webapps-2026-09-30_124302.tar.gz.manifest
-rw-r--r-- 1 root root   99 webapps-2026-09-30_124302.tar.gz.sha256
```

Three files per backup. The archive, the manifest it was verified against, and a
checksum of the archive used later for the off-VM copy. Keeping the manifest
next to the archive is what makes an independent re-verification possible weeks
later, on another machine.

## The failure drill

A verifier that only ever prints success proves nothing. The drill tampers with
the manifest, expects a non-zero exit, then restores the manifest and expects a
pass - so the tool is shown to discriminate rather than to always fail:

```bash
bash scripts/backup-failure-drill.sh
```

```
Target archive: webapps-2026-09-30_124302.tar.gz

--- manifest tampered, verifying ---
RESTORE MISMATCH: /var/backups/tomcat/webapps-2026-09-30_124302.tar.gz
exit code: 1

--- manifest restored, verifying again ---
RESTORE VERIFIED: 5 files match (/var/backups/tomcat/webapps-2026-09-30_124302.tar.gz)

DRILL PASSED: the tampered backup was rejected with a non-zero exit code
```

The drill script asserts the outcome, so it fails loudly if the verification
ever silently breaks.

## The check that exists because of a real incident

The script refuses to run if the source directory has no files:

```bash
if [ -z "$(manifest "$SRC")" ]; then
  echo "ERROR: $SRC contains no files, refusing to write a meaningless backup" >&2
  exit 1
fi
```

Without it, an empty `webapps/` produces an empty archive and an empty manifest,
the diff of two empty manifests passes, and the tool cheerfully prints
`RESTORE VERIFIED: 0 files match`. That is a backup that protects nothing while
looking healthy.

This is not a hypothetical. During M5 the deployment directory really was empty
for a while, and a tool without this guard would have "verified" seven backups
of nothing overnight. The guard is cheap; the false confidence is not.

## Off-VM copy

```bash
bash scripts/pull-backups.sh
```

```
receiving incremental file list
webapps-2026-09-30_124302.tar.gz
webapps-2026-09-30_124302.tar.gz.manifest
webapps-2026-09-30_124302.tar.gz.sha256

Verifying the archives survived the transfer:
webapps-2026-09-30_124302.tar.gz: OK
```

The archives land in `~/kvm-lab-backups` on the KVM host, outside the VM they
protect, and the checksum computed *on the VM* is re-checked *here*. A transfer
that corrupted the file could not pass this.

This is still the same physical machine, which is a real limitation: it survives
losing the VM, not losing the host. Off-host storage (object storage, or another
machine) is the next step for anything that matters, and the README says so
plainly rather than implying full disaster recovery.

## Scheduling

```ini
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
```

`Persistent=true` matters here specifically because this lab's VM is frequently
switched off. Without it, a missed 02:00 run is simply skipped. With it, systemd
runs the backup on next boot and catches up.

```
$ systemctl list-timers tomcat-backup.timer
NEXT                        LEFT     UNIT                ACTIVATES
Thu 2026-10-01 02:00:00 UTC  13h     tomcat-backup.timer tomcat-backup.service
```

Retention is 7 days, and the `find ... -delete` also removes the orphaned
manifests and checksums. An orphaned manifest is worse than no manifest.

## Caveat: the guest clock is not trustworthy here

`tar` printed this on every run:

```
tar: ./labapp/work.jsp: time stamp 2026-09-30 17:06:02 is 15767.5 s in the future
```

4.4 hours, which is the offset between this host's timezone and the guest's UTC.
The guest's clock jumps around because the VMs get power-cycled and because the
M5 memory-state revert rewinds the guest clock (the guest logs
`Clock change detected` afterwards). Files written before a jump keep the old
timestamp.

Harmless for this backup, because verification compares file *contents* against a
manifest and never looks at timestamps. Worth knowing anyway: do not build
anything on guest file mtimes in this environment. If timestamps mattered, the
fix is a working guest clock, not a smarter archive.
