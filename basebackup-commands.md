# pg_basebackup - Physical Backup & Restore

## What is pg_basebackup?

pg_basebackup creates a binary copy of the entire PostgreSQL 
data directory. Think of it like taking a photo of the entire 
database server — everything included.

### Analogy
```
pg_dump     = photocopying individual pages of a book
pg_basebackup = scanning the entire book as one image
```

## Why we need BOTH HA Replicas AND Backups

This is the most important concept:

### HA Replicas protect against INFRASTRUCTURE failure
```
Server hardware dies → replica takes over automatically
Network failure      → another node handles traffic
PostgreSQL crash     → Patroni promotes replica
```

### Backups protect against DATA failure
```
Developer runs: DELETE FROM orders;  (forgot WHERE clause!)
  Primary:  0 orders ❌
  Replica1: 0 orders ❌  (copied the delete!)
  Replica2: 0 orders ❌  (copied the delete!)
  
Replica is a MIRROR — copies everything including mistakes!
Only backup from BEFORE the mistake can restore data.
```

### What if ALL servers crash simultaneously?

This can happen in real life:
- Data center fire
- Power outage affecting all servers
- Natural disaster (flood, earthquake)
- Cloud region outage (AWS us-east-1 has gone down!)
```
Without offsite backup:
  Primary  → CRASHED ❌
  Replica1 → CRASHED ❌
  Replica2 → CRASHED ❌
  Result   → Data GONE FOREVER ❌

With offsite backup (S3):
  Primary  → CRASHED ❌
  Replica1 → CRASHED ❌
  Replica2 → CRASHED ❌
  S3 Backup → SAFE ✅ (different location!)
  Result   → Restore to new server in 1 hour ✅
```

## The 3-2-1 Backup Rule (Industry Standard)
```
3 → Keep 3 copies of data
2 → Store on 2 different types of storage  
1 → Keep 1 copy offsite (different location)

Example:
  Copy 1: Primary database (Mumbai server)
  Copy 2: Replica (Chennai server - different city)
  Copy 3: Backup on AWS S3 (cloud - different region)
```

## Protection Layers

| Scenario | HA Replica | Backup | HA + Backup |
|---|---|---|---|
| One server crashes | ✅ | ✅ | ✅ |
| All servers crash | ❌ | ✅ | ✅ |
| Accidental DELETE | ❌ | ✅ | ✅ |
| DROP TABLE mistake | ❌ | ✅ | ✅ |
| Ransomware attack | ❌ | ✅ | ✅ |
| Data center fire | ❌ | ✅* | ✅* |
| Restore to yesterday | ❌ | ✅ | ✅ |

*Only if backup stored offsite

## When to use pg_basebackup vs pg_dump
```
Use pg_dump when:
  ✅ Restore just one table
  ✅ Copy one database to test server
  ✅ Small database under 10GB
  ✅ Need human readable backup

Use pg_basebackup when:
  ✅ Entire server disaster recovery
  ✅ Setting up new replicas
  ✅ Large databases over 50GB (5-10x faster restore)
  ✅ Need Point in Time Recovery (PITR)
```

## Speed Comparison (500GB database)
```
pg_dump restore:      4-6 hours  ❌ slow
pg_basebackup restore: 30-45 min ✅ fast

Why faster?
pg_dump:        re-executes every INSERT, rebuilds all indexes
pg_basebackup:  copies binary files directly, no rebuilding
```

## Backup Command
```bash
pg_basebackup \
  -h localhost \        # host to connect to
  -p 5432 \             # PostgreSQL port
  -U replicator \       # MUST use replication user
  -D /tmp/backup \      # destination directory
  -F t \                # tar format (creates .tar.gz)
  -z \                  # compress with gzip
  -P \                  # show progress
  -v                    # verbose output
```

## Why replicator user?
```
pg_basebackup uses replication protocol internally
Same protocol replicas use to stream WAL
Only users with REPLICATION privilege can use it

Without REPLICATION privilege:
  FATAL: must be superuser or replication role ❌

Grant it with:
  CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '...';
```

## Backup Output Files

| File | Contents | Needed for restore? |
|---|---|---|
| `base.tar.gz` | Entire data directory | Yes - required |
| `pg_wal.tar.gz` | WAL during backup | Yes - for consistency |
| `backup_manifest` | File checksums | Optional - integrity check |

## Why both base.tar.gz AND pg_wal.tar.gz needed?
```
Backup takes 30 minutes for large database.
During those 30 minutes database keeps running.
New transactions happen continuously.

base.tar.gz alone = INCONSISTENT (files from different times)
base.tar.gz + pg_wal.tar.gz = CONSISTENT ✅

pg_wal.tar.gz captures all changes during backup.
On restore: extract base → apply WAL → consistent state!
```

## Complete Restore Steps

### Step 1 - Stop the node
```bash
docker stop pg-node3
```

### Step 2 - Wipe existing data (simulate disk failure)
```bash
docker run --rm \
  -v pg-patroni-cluster_pg_node3_data:/data \
  alpine \
  sh -c "find /data -mindepth 1 -delete && echo 'Data wiped!'"
```

### Step 3 - Restore backup into empty volume
```bash
docker run --rm \
  -v pg-patroni-cluster_pg_node3_data:/data \
  -v ~/Desktop/pg-backups/physical:/backup \
  postgres:15 \
  bash -c "cd /data && tar -xzf /backup/base.tar.gz && echo 'Restored!'"
```

### Step 4 - Fix permissions (CRITICAL step)
```bash
docker run --rm \
  -v pg-patroni-cluster_pg_node3_data:/data \
  postgres:15 \
  bash -c "chown -R postgres:postgres /data && chmod 700 /data"
```

Why fix permissions?
```
tar extracted files as root user
PostgreSQL REFUSES to start if data dir owned by root
PostgreSQL requires:
  Owner: postgres user
  Permission: 700 (only owner can read/write)
  
700 = owner can read+write+execute
      group cannot access
      others cannot access
```

### Step 5 - Start node and verify
```bash
docker start pg-node3
sleep 20
patronictl -c /etc/patroni.yml list
```

Patroni automatically:
- Detects node rejoining
- Connects it to current leader
- Streams missing WAL
- Node catches up to Lag=0

## Production Backup Schedule (Automated with CRON)
```
Never backup manually in production!
Use CRON to automate everything.

CRON syntax:
  * * * * * command
  │ │ │ │ │
  │ │ │ │ └── Day of week
  │ │ │ └──── Month
  │ │ └────── Day of month
  │ └──────── Hour
  └────────── Minute

Production schedule:
  0 2 * * *    → pg_dumpall nightly at 2 AM
  0 0 * * 0    → pg_basebackup weekly on Sunday
  */5 * * * *  → WAL archiving every 5 minutes (PITR)
```

## Backup Storage (Never same server as database!)
```
WRONG:
  Database server → also stores backup
  Server crashes  → backup also gone! ❌

CORRECT:
  Database server → backup → AWS S3 (different region)
  Server crashes  → S3 backup safe ✅
  Restore to new server from S3 → back online ✅
```

## Sequence Fix After Restore

If tables use SERIAL/sequences, fix after restore:
```sql
-- Find sequence name
\d tablename

-- Fix sequence to continue from max id
SELECT setval('sequence_name', (SELECT MAX(id) FROM tablename));
```

Why needed?
```
Backup saves data but sequence counter may reset
Without fix: INSERT fails with "null value in id" error
With fix: INSERT continues from correct next id
```

## Interview Questions & Answers

**Q: What is the difference between pg_dump and pg_basebackup?**
pg_dump exports data as SQL statements — good for single
database or table restore. pg_basebackup copies binary files
of entire data directory — faster for large databases and
required for PITR. I use both: pg_dump for logical backups
and pg_basebackup as base for point-in-time recovery.

**Q: Why do we need backups if we have HA replicas?**
Replicas are mirrors — they copy everything from primary
including mistakes. If developer accidentally deletes all
data, that delete is instantly replicated to all replicas.
Only a backup taken before the mistake can restore the data.
HA protects against infrastructure failure, backup protects
against data failure. We need both.

**Q: What is the 3-2-1 backup rule?**
3 copies of data, on 2 different storage types, with 1 copy
offsite. In practice: primary database, replica on different
server, backup on S3 in different region. Even if entire
data center burns down, S3 backup is safe.

**Q: Why must you fix permissions after restore?**
pg_basebackup or tar extraction creates files owned by root.
PostgreSQL refuses to start if data directory is owned by
root or has permissions other than 700. Fix with:
chown -R postgres:postgres /data && chmod 700 /data

**Q: What if ALL servers crash simultaneously?**
This is why we store backups offsite. If all servers in
same data center crash (fire, power outage), the offsite
backup on S3 in different region is still safe. We spin up
new servers, restore from S3, and are back online within
1-2 hours.
