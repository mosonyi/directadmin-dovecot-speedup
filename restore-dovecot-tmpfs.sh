#!/bin/bash
rsync -a /var/backups/dovecot/control/ /var/lib/dovecot-control/
rsync -a /var/backups/dovecot/index/ /var/lib/dovecot-index/
rsync -a /var/backups/dovecot/cache/ /var/lib/dovecot-cache/