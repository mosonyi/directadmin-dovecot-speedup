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