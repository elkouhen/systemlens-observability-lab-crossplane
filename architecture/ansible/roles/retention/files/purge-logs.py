#!/usr/bin/env python3
"""Supprimer les archives de logs expirées sans toucher aux fichiers ouverts."""
import glob
import os
from pathlib import Path
import time

patterns = [
    '/var/log/kafka/*.log.*',
    '/var/log/mongodb/*.log.*',
    '/var/log/postgresql/*.log.*',
    '/var/log/haproxy.log-*',
    '/var/log/messages-*', '/var/log/secure-*', '/var/log/cron-*',
    '/var/log/maillog-*', '/var/log/spooler-*',
    '/opt/Elastic/Agent/data/elastic-agent-*/logs/*.ndjson',
    '/opt/Elastic/Agent/data/elastic-agent-*/logs/*/*.ndjson',
]
opened = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        stat = os.stat(fd)
        opened.add((stat.st_dev, stat.st_ino))
    except FileNotFoundError:
        pass
cutoff = time.time() - 86400
removed = 0
for pattern in patterns:
    for filename in glob.glob(pattern):
        path = Path(filename)
        try:
            stat = path.lstat()
            if path.is_symlink() or not path.is_file():
                continue
            if stat.st_mtime < cutoff and (stat.st_dev, stat.st_ino) not in opened:
                path.unlink()
                removed += 1
        except FileNotFoundError:
            pass
print(f'Archives de logs expirées supprimées : {removed}')
