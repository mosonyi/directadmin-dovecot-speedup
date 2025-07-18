#!/bin/bash

LOCKFILE="/var/lock/dovecot-tmpfs.lock"
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

restore_dir() {
  SRC="$1"
  DST="$2"

  echo "[$(date)] Restoring $SRC to $DST"
  rsync -a "$SRC/" "$DST/"
}

restore_dir "/var/backups/dovecot/control" "/var/lib/dovecot-control"
restore_dir "/var/backups/dovecot/index" "/var/lib/dovecot-index"
restore_dir "/var/backups/dovecot/cache" "/var/lib/dovecot-cache"

flock -u 200
rm -f "$LOCKFILE"