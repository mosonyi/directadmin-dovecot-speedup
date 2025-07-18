# 📄 Optimizing Dovecot Performance on DirectAdmin with Maildir and HDD RAID1

## 🧠 Problem Summary

On a DirectAdmin-based mail server with:
- **Maildir storage format**
- **HDD RAID1 array**
- **Large user mailboxes (gigabytes of mail data)**

...Dovecot performance was **extremely slow**, especially during:
- IMAP sync
- Searching
- Index rebuilds
- Concurrent logins

Despite having high server specs and no network bottlenecks, IMAP performance was degraded due to **I/O latency** on the spinning disks.

## 🎯 Goal

Improve Dovecot's speed and responsiveness **without changing storage format** (Maildir) and **without SSDs** by optimizing:

- Indexing
- Cache access
- Mail control file I/O

## ✅ Final Solution (What Fixed the Problem)

### ✨ Move Dovecot Indexes and Caches to RAM (`tmpfs`)

**Dovecot settings:**

/etc/dovecot/conf.d/tuning.conf

```ini
mail_index_path = /var/lib/dovecot-index/%{user | domain}/%{user | username}
mail_cache_path = /var/lib/dovecot-cache/%{user | domain}/%{user | username}
mail_control_path = /var/lib/dovecot-control/%{user | domain}/%{user | username}
```

These paths point **outside** the Maildir structure to **RAM-based filesystems**.

### 💾 `/etc/fstab` configuration

```fstab
tmpfs /var/lib/dovecot-index tmpfs size=1024M,mode=0755 0 0
tmpfs /var/lib/dovecot-cache tmpfs size=2048M,mode=0755 0 0
tmpfs /var/lib/dovecot-control tmpfs size=1024M,mode=0755 0 0
```

Then mount the tmpfs volumes:
```bash
mkdir -p /var/lib/dovecot-index /var/lib/dovecot-cache /var/lib/dovecot-control
mount -a
```

## ⚡ Result

After applying these changes:

| Action | Before | After |
|--------|--------|-------|
| IMAP folder sync | 1–2 Mbit/s | 30–100 Mbit/s |
| Thunderbird startup | 10–30 seconds | 1–3 seconds |
| IMAP search (large mailboxes) | Several seconds | Instant or <1s |
| Concurrent logins | High I/O wait | No noticeable delay |

## 📌 Why It Works

- **Maildir is I/O-heavy**: It stores each message as a file. Indexes, cache, and control files create heavy metadata churn — especially on HDDs.
- **Moving indexes and cache to tmpfs (RAM)** removes almost all metadata disk I/O from login/search operations.
- **Only message body reads still hit the disk**, which is tolerable because it happens less frequently and sequentially.

## 🛠️ Additional Recommendations

1. **Monitor RAM usage**
   - Ensure your system has enough free RAM to hold indexes (about 5–10 MB per active user).
   - Use `du -sh /var/lib/dovecot-*` to estimate needed `tmpfs` size.

2. **Restart Dovecot after changes**
   ```bash
   systemctl restart dovecot
   ```

## ✅ Final Notes

This is a **high-impact, low-cost optimization** that transforms Maildir performance on HDDs, especially for busy or large mailboxes. No need for SSDs, mail format changes, or hardware upgrades.


---

## 🛡️ Persistence for Dovecot tmpfs Directories (Backup and Restore)

Because the following directories are mounted in RAM (`tmpfs`), they are lost on reboot. This section shows how to automatically **backup and restore** their contents:

- `/var/lib/dovecot-control`
- `/var/lib/dovecot-index`
- `/var/lib/dovecot-cache`

### 📦 1. Create Persistent Backup Locations

Run once:

```bash
sudo mkdir -p /var/backups/dovecot/{control,index,cache}
sudo chown -R dovecot:mail /var/backups/dovecot/
```

---

### 📥 2. Backup Script (`/usr/local/bin/backup-dovecot-tmpfs.sh`)

Create the file:

```bash
sudo vi /usr/local/bin/backup-dovecot-tmpfs.sh
```

Contents:

```bash
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
```

Then make it executable:

```bash
sudo chmod +x /usr/local/bin/backup-dovecot-tmpfs.sh
```

---

### 📤 3. Restore Script (`/usr/local/bin/restore-dovecot-tmpfs.sh`)

Create the file:

```bash
sudo nano /usr/local/bin/restore-dovecot-tmpfs.sh
```

Contents:

```bash
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
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/restore-dovecot-tmpfs.sh
```

---

### ⏰ 4. Automatic Backup with Cron

Edit root's crontab:

```bash
sudo crontab -e
```

Add the following line to run the backup every 15 minutes:

```cron
*/15 * * * * /usr/local/bin/backup-dovecot-tmpfs.sh
```

---

### ⚙️ 5. Systemd Service to Restore at Boot

Create a systemd unit file:

```bash
sudo nano /etc/systemd/system/dovecot-tmpfs-restore.service
```

Contents:

```ini
[Unit]
Description=Restore Dovecot tmpfs directories from backup
Before=dovecot.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restore-dovecot-tmpfs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable the restore service:

```bash
sudo systemctl daemon-reexec
sudo systemctl enable dovecot-tmpfs-restore.service
```

Test it:

```bash
sudo systemctl start dovecot-tmpfs-restore.service
```

If the `tmpfs` directories are mounted and a backup exists, this will restore the Dovecot state automatically.

---

## 📂 Migrating Subscriptions and Metadata Files to Dovecot Control Path

To improve performance and consistency, it is also recommended to move the following metadata files into the `mail_control_path` (`/var/lib/dovecot-control`):

- `subscriptions`
- `dovecot-keywords`
- `dovecot-uidvalidity*`

You can automate this process with the following script:

migrate-dovecot-files.sh

```bash
for name in subscriptions dovecot-keywords "dovecot-uidvalidity*"; do
  find /home/ -type f -name "$name" | while read filepath; do
      relative_path="${filepath#/home/}"
      target_file="/var/lib/dovecot-control/$relative_path"
      target_dir="$(dirname "$target_file")"

      # Create target directory if it doesn't exist
      mkdir -p "$target_dir"

      # Save permissions and ownership
      perms=$(stat -c "%a" "$filepath")
      owner=$(stat -c "%u" "$filepath")
      group=$(stat -c "%g" "$filepath")

      # Move the file
      cp -p "$filepath" "$target_file" && rm -f "$filepath"

      # Restore permissions and ownership
      chown $owner:$group "$target_file"
      chmod $perms "$target_file"
  done
done
```

### 💡 Notes:
- This script scans `/home/` for the named files and moves them into the appropriate path under `/var/lib/dovecot-control`, preserving their permissions.
- After running the script, Dovecot will find these files in `mail_control_path` as intended, ensuring better isolation and speed, especially on HDD setups.
- Run the script as root for proper access to all user directories.

---
