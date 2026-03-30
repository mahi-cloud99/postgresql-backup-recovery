# PITR Manual Restore Steps

## What we practiced

Recovery target time: 2026-03-30 02:41:58
Disaster: DELETE FROM employees (all 14 rows deleted)
Result after PITR: all 14 rows restored ✅

## Step by step manual restore

### Step 1 - Enable WAL archiving
```bash
docker exec $CONTAINER psql -U admin -d postgres \
  -c "ALTER SYSTEM SET archive_mode = 'on';"

docker exec $CONTAINER psql -U admin -d postgres \
  -c "ALTER SYSTEM SET archive_command = \
      'cp %p /var/lib/postgresql/wal_archive/%f';"

docker exec $CONTAINER psql -U admin -d postgres \
  -c "ALTER SYSTEM SET archive_timeout = '60';"
```

### Step 2 - Restart to apply settings
```bash
docker exec $CONTAINER patronictl \
  -c /etc/patroni.yml restart pg-cluster $CONTAINER --force
```

### Step 3 - Verify archiving is on
```bash
docker exec $CONTAINER psql -U admin -d postgres \
  -c "SELECT name, setting FROM pg_settings
      WHERE name IN
      ('archive_mode','archive_command','archive_timeout');"
```

### Step 4 - Take base backup
```bash
docker exec $CONTAINER pg_basebackup \
  -h localhost -p 5432 -U replicator \
  -D /tmp/pitr_base_backup \
  -F t -z -P -v --wal-method=stream

docker cp $CONTAINER:/tmp/pitr_base_backup \
  ~/Desktop/pg-backups/pitr/
```

### Step 5 - Record recovery target time
```bash
# WRITE THIS DOWN before disaster happens!
docker exec $CONTAINER psql -U admin -d postgres \
  -c "SELECT NOW() AS recovery_target_time;"
```

### Step 6 - Force WAL archive after disaster
```bash
docker exec $CONTAINER psql -U admin -d postgres \
  -c "SELECT pg_switch_wal();"

sleep 65

docker cp $CONTAINER:/var/lib/postgresql/wal_archive \
  ~/Desktop/pg-backups/pitr/
```

### Step 7 - Create restore container
```bash
docker run -d \
  --name pg-pitr-restore \
  --network pg-patroni-cluster_patroni_net \
  -v ~/Desktop/pg-backups/pitr/pitr_base_backup:/backup \
  -v ~/Desktop/pg-backups/pitr/wal_archive:/wal_archive \
  postgres:15 \
  sleep infinity
```

### Step 8 - Extract base backup
```bash
docker exec pg-pitr-restore bash -c "
  mkdir -p /pitr_data &&
  cd /pitr_data &&
  tar -xzf /backup/base.tar.gz
"
```

### Step 9 - Copy WAL archive
```bash
docker exec pg-pitr-restore bash -c "
  cp -r /wal_archive /pitr_data/wal_archive_restore
"
```

### Step 10 - Write recovery config
```bash
docker exec pg-pitr-restore bash -c "
cat >> /pitr_data/postgresql.auto.conf << 'EOF'
restore_command = 'cp /pitr_data/wal_archive_restore/%f %p'
recovery_target_time = '2026-03-30 02:41:58'
recovery_target_action = 'promote'
EOF
"
```

### Step 11 - Create recovery.signal
```bash
docker exec pg-pitr-restore bash -c "
  touch /pitr_data/recovery.signal &&
  chown -R postgres:postgres /pitr_data &&
  chmod 700 /pitr_data
"
```

### Step 12 - Start PostgreSQL in recovery mode
```bash
docker exec -d pg-pitr-restore bash -c "
  gosu postgres postgres \
    -D /pitr_data -p 5433 \
    -c hba_file=/pitr_data/pg_hba.conf \
    -c ident_file=/pitr_data/pg_ident.conf \
    >> /tmp/pitr_recovery.log 2>&1
"
sleep 15
docker exec pg-pitr-restore bash -c "cat /tmp/pitr_recovery.log"
```

### Step 13 - Verify restored data
```bash
docker exec pg-pitr-restore bash -c "
  gosu postgres psql -p 5433 -U admin -d postgres \
    -c 'SELECT COUNT(*) FROM employees;'
"
```

### Step 14 - Cleanup
```bash
docker stop pg-pitr-restore
docker rm pg-pitr-restore
```

## Key log messages during recovery
```
starting point-in-time recovery ← PITR started
restored log file "000000030000000000000007" ← WAL replaying
recovery stopping before commit of transaction ← STOPPED at target!
archive recovery complete ← done!
database system is ready to accept connections ← success!
```
