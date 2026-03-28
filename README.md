# PostgreSQL Backup & Restore Practice

## What is covered
- pg_dump logical backup
- pg_restore restore
- pg_dumpall full server backup
- Selective table restore
- Backup script with rotation

## Files
| File | Purpose |
|---|---|
| `backup-commands.md` | Complete command reference |
| `backup.sh` | Automated backup script |

## Quick Start

### Take backup
```bash
pg_dump -U admin -d mydb -F c -f backup.dump
```

### Restore backup
```bash
pg_restore -U admin -d mydb -v backup.dump
```

### Restore single table
```bash
pg_restore -U admin -d mydb -t tablename \
  --clean --if-exists -v backup.dump
```

## Practice Setup
Uses PostgreSQL HA Patroni cluster:
https://github.com/mahi-cloud99/postgresql-ha-patroni

## Related Repos
- Manual HA: https://github.com/mahi-cloud99/postgresql-ha-manual
- Automatic HA: https://github.com/mahi-cloud99/postgresql-ha-patroni
