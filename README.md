# PostgreSQL Backup & Restore Practice

## Overview
Complete backup and restore practice for PostgreSQL.
Covers logical backup (pg_dump) and physical backup
(pg_basebackup). Uses Patroni HA cluster for practice.

## Repository Structure
```
pg-backup-practice/
├── README.md                  # This file
├── backup.sh                  # Automated backup script
├── backup-commands.md         # pg_dump complete reference
└── basebackup-commands.md     # pg_basebackup complete reference
```

## Key Concepts

### Why we need BOTH HA and Backup
```
HA Replicas = protection against INFRASTRUCTURE failure
              Server crashes → failover to replica

Backup      = protection against DATA failure
              Data deleted/corrupted → restore from backup

Replica copies EVERYTHING from primary including mistakes!
Only backup can go back in time before the mistake.
```

### The 3-2-1 Rule
```
3 copies → primary + replica + backup
2 types  → server storage + cloud storage
1 offsite → backup on S3 in different region
```

## Backup Types Covered

| Type | Tool | Best For |
|---|---|---|
| Logical | pg_dump | Single table/database restore |
| Logical All | pg_dumpall | Full server + users/roles |
| Physical | pg_basebackup | Large DB, disaster recovery, PITR |

## Quick Reference

### pg_dump (logical backup)
```bash
# Backup single database
pg_dump -U admin -d mydb -F c -f backup.dump

# Backup all databases + users
pg_dumpall -U admin -f all.sql

# Restore full database
pg_restore -U admin -d mydb -v backup.dump

# Restore single table
pg_restore -U admin -d mydb -t tablename \
  --clean --if-exists -v backup.dump
```

### pg_basebackup (physical backup)
```bash
# Take physical backup
pg_basebackup -h localhost -p 5432 \
  -U replicator -D /tmp/backup \
  -F t -z -P -v

# Restore (extract to data volume)
tar -xzf base.tar.gz -C /var/lib/postgresql/data/

# Fix permissions after restore
chown -R postgres:postgres /data
chmod 700 /data
```

## Practice Environment
Uses PostgreSQL HA Patroni cluster:
https://github.com/mahi-cloud99/postgresql-ha-patroni

## Related Repositories
- Manual HA: https://github.com/mahi-cloud99/postgresql-ha-manual
- Automatic HA: https://github.com/mahi-cloud99/postgresql-ha-patroni
