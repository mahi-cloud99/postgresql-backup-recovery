# PostgreSQL Backup & Restore Commands Reference

## pg_dump — Logical Backup

### Backup single database (custom format - recommended)
```bash
pg_dump -U admin -d mydb -F c -f backup.dump
```

### Backup single database (plain SQL - human readable)
```bash
pg_dump -U admin -d mydb -F p -f backup.sql
```

### Backup single table only
```bash
pg_dump -U admin -d mydb -t tablename -F c -f table_backup.dump
```

### Backup all databases + users + roles
```bash
pg_dumpall -U admin -f all_databases.sql
```

### List contents of a backup file
```bash
pg_restore --list backup.dump
```

## pg_restore — Restore from pg_dump

### Restore full database
```bash
pg_restore -U admin -d mydb -v backup.dump
```

### Restore single table
```bash
pg_restore -U admin -d mydb -t tablename --clean --if-exists -v backup.dump
```

### Restore all databases
```bash
psql -U admin -f all_databases.sql
```

## Flag Reference

| Flag | Meaning |
|---|---|
| `-U` | Username |
| `-d` | Database name |
| `-F c` | Custom format (recommended) |
| `-F p` | Plain SQL format |
| `-F t` | Tar format |
| `-f` | Output file |
| `-v` | Verbose output |
| `-t` | Single table only |
| `--clean` | Drop before restore |
| `--if-exists` | Skip error if not exists |
| `-P` | Show progress |
| `-z` | Compress output |

## Format Comparison

| Format | Size | Restore Speed | Single Table | Use When |
|---|---|---|---|---|
| Plain (-F p) | Large | Slow | No | Need to read/edit backup |
| Custom (-F c) | Small | Fast | Yes | Production (always) |
| Directory (-F d) | Medium | Fastest (parallel) | Yes | Very large databases |
| Tar (-F t) | Medium | Medium | Yes | Portability |

## Real Production Scenarios

### Scenario 1: Developer deleted table by mistake
```bash
# Restore just that table
pg_restore -U admin -d mydb \
  -t deleted_table \
  --clean --if-exists \
  -v backup.dump
```

### Scenario 2: Full database corruption
```bash
# Drop and recreate database
psql -U admin -c "DROP DATABASE mydb;"
psql -U admin -c "CREATE DATABASE mydb;"

# Restore everything
pg_restore -U admin -d mydb -v backup.dump
```

### Scenario 3: Copy database to test environment
```bash
# Backup production
pg_dump -U admin -d proddb -F c -f prod_backup.dump

# Restore to test
pg_restore -U admin -d testdb -v prod_backup.dump
```

### Scenario 4: Before running risky migration
```bash
# Always backup before major changes!
pg_dump -U admin -d mydb -F c \
  -f "pre_migration_$(date +%Y%m%d_%H%M%S).dump"

# Run your migration
# If something goes wrong → restore from above backup
```

## Backup Schedule (Production Best Practice)
```
Every night midnight  → pg_dumpall (full backup)
Every hour           → WAL archiving (for PITR)
Before any migration → manual pg_dump
Keep last 7 days     → auto delete older backups
Store offsite        → S3 / Google Cloud Storage
```

## Interview Questions & Answers

**Q: What is the difference between pg_dump and pg_dumpall?**
pg_dump backs up a single database.
pg_dumpall backs up all databases plus global objects
like roles and tablespaces. Always use pg_dumpall for
full server backup so user accounts are also saved.

**Q: What backup format do you use in production?**
Custom format (-F c). It is compressed, supports
parallel restore, and allows restoring single tables.
Only use plain format when I need to read or edit
the backup manually.

**Q: How do you restore a single table?**
pg_restore -t tablename --clean --if-exists -v backup.dump
The --clean flag drops existing table first to avoid
duplicate key errors.

**Q: How often should you backup?**
Depends on RPO (Recovery Point Objective).
For most production: nightly full backup with
continuous WAL archiving for point-in-time recovery.
