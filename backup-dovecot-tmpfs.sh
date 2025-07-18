#!/bin/bash
rsync -a --delete /var/lib/dovecot-control/ /var/backups/dovecot/control/
rsync -a --delete /var/lib/dovecot-index/ /var/backups/dovecot/index/
rsync -a --delete /var/lib/dovecot-cache/ /var/backups/dovecot/cache/