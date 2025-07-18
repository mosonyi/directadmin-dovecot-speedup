#!/bin/bash

LOCKFILE="/var/lock/dovecot-tmpfs-backup.lock"
LOCK_MAX_AGE=3600

if [ -f "$LOCKFILE" ]; then
  AGE=$(($(date +%s) - $(stat -c %Y "$LOCKFILE")))
  if [ "$AGE" -gt "$LOCK_MAX_AGE" ]; then
    echo "[$(date)] Lockfile too old ($AGE sec), removing stale lock."
    rm -f "$LOCKFILE"
  fi
fi

exec 200>"$LOCKFILE"
flock -n 200 || { echo "[$(date)] Backup or restore already running, exiting."; exit 1; }

# dovecot tmpfs backup with safeguard
check_and_backup() {
  SRC="$1"
  DST="$2"
  MIN_FILES=20

  COUNT=$(find "$SRC" -type f 2>/dev/null | wc -l)

  if [ "$COUNT" -lt "$MIN_FILES" ]; then
    echo "[$(date)] Skipping backup of $SRC: only $COUNT files found (probably empty tmpfs)"
    return
  fi

  echo "[$(date)] Backing up $SRC to $DST"
  rsync -a --delete "$SRC/" "$DST/"
}

check_and_backup "/var/lib/dovecot-control" "/var/backups/dovecot/control"
check_and_backup "/var/lib/dovecot-index" "/var/backups/dovecot/index"
check_and_backup "/var/lib/dovecot-cache" "/var/backups/dovecot/cache"

flock -u 200
rm -f "$LOCKFILE"