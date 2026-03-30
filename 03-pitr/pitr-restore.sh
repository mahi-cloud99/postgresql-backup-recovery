#!/bin/bash
#==============================================================
# PITR Restore Script
# Run MANUALLY when disaster happens
# Usage: ./restore.sh "YYYY-MM-DD HH:MM:SS"
# Example: ./restore.sh "2026-03-30 09:04:59"
#==============================================================

set -e

# ── CONFIGURATION ─────────────────────────────────────────────
CONTAINER_NAME="pg-node1"
LOG_FILE="/tmp/pitr_restore.log"
BASE_BACKUP_DIR="$HOME/Desktop/pg-backups/pitr/pitr_base_backup"
WAL_ARCHIVE_DIR="$HOME/Desktop/pg-backups/pitr/wal_archive"
# ──────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# ── CHECK USAGE ───────────────────────────────────────────────
if [ -z "$1" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    echo "Example: $0 '2026-03-30 09:04:59'"
    echo ""
    echo "Tip: Use time BEFORE the disaster happened"
    exit 1
fi
RECOVERY_TARGET_TIME="$1"

# ── CONFIRMATION ──────────────────────────────────────────────
confirm_restore() {
    echo ""
    echo "═══════════════════════════════════════"
    echo "          PITR RESTORE CONFIRMATION"
    echo "═══════════════════════════════════════"
    echo "Target time:  $RECOVERY_TARGET_TIME"
    echo "Base backup:  $BASE_BACKUP_DIR"
    echo "WAL archive:  $WAL_ARCHIVE_DIR"
    echo ""
    echo "⚠️  WARNING: Current data will be replaced!"
    echo "    Type YES to continue, anything else to cancel:"
    read CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        log "Restore cancelled"
        exit 0
    fi
    log "Restore confirmed by user"
}

check_files_exist() {
    log "Checking required files..."
    if [ ! -f "$BASE_BACKUP_DIR/base.tar.gz" ]; then
        log "ERROR: base.tar.gz not found at $BASE_BACKUP_DIR"
        exit 1
    fi
    log "base.tar.gz found ✓"
    if [ ! -d "$WAL_ARCHIVE_DIR" ]; then
        log "ERROR: WAL archive not found: $WAL_ARCHIVE_DIR"
        exit 1
    fi
    local WAL_COUNT=$(ls $WAL_ARCHIVE_DIR | wc -l)
    log "WAL archive: $WAL_COUNT files ✓"
}

stop_postgresql() {
    log "Stopping $CONTAINER_NAME..."
    docker stop $CONTAINER_NAME
    sleep 5
    log "Container stopped"
}

clear_data_volume() {
    log "Clearing data volume..."
    docker run --rm \
        -v pg-patroni-cluster_pg_node1_data:/data \
        alpine \
        sh -c "find /data -mindepth 1 -delete && echo Cleared"
    log "Data volume cleared"
}

restore_base_backup() {
    log "Restoring base backup..."
    docker run --rm \
        -v pg-patroni-cluster_pg_node1_data:/data \
        -v $BASE_BACKUP_DIR:/backup \
        postgres:15 \
        bash -c "cd /data && tar -xzf /backup/base.tar.gz &&
                 echo 'Base backup extracted!'"
    log "Base backup restored"
}

copy_wal_archive() {
    log "Copying WAL archive..."
    docker run --rm \
        -v pg-patroni-cluster_pg_node1_data:/data \
        -v $WAL_ARCHIVE_DIR:/wal_archive \
        postgres:15 \
        bash -c "cp -r /wal_archive /data/wal_archive_restore &&
                 echo 'WAL copied!' &&
                 ls /data/wal_archive_restore/ | wc -l &&
                 echo WAL files"
    log "WAL archive copied"
}

write_recovery_config() {
    log "Writing recovery config..."
    log "Target: $RECOVERY_TARGET_TIME"

    docker run --rm \
        -v pg-patroni-cluster_pg_node1_data:/data \
        postgres:15 \
        bash -c "
cat >> /data/postgresql.auto.conf << EOF
restore_command = 'cp /data/wal_archive_restore/%f %p'
recovery_target_time = '$RECOVERY_TARGET_TIME'
recovery_target_action = 'promote'
EOF
echo 'Config written!'
tail -4 /data/postgresql.auto.conf
"
    log "Recovery config written"
}

create_recovery_signal() {
    log "Creating recovery.signal..."
    docker run --rm \
        -v pg-patroni-cluster_pg_node1_data:/data \
        postgres:15 \
        bash -c "
            touch /data/recovery.signal &&
            chown -R postgres:postgres /data &&
            chmod 700 /data &&
            echo 'Signal created, permissions fixed!'
        "
    log "recovery.signal created"
}

start_recovery() {
    log "Starting PITR recovery container..."

    # Remove old temp container if exists
    docker stop pg-pitr-temp 2>/dev/null || true
    docker rm pg-pitr-temp 2>/dev/null || true

    docker run -d \
        --name pg-pitr-temp \
        --network pg-patroni-cluster_patroni_net \
        -v pg-patroni-cluster_pg_node1_data:/pitr_data \
        postgres:15 \
        sleep infinity

    sleep 3

    docker exec -d pg-pitr-temp bash -c "
        gosu postgres postgres \
            -D /pitr_data \
            -p 5433 \
            -c hba_file=/pitr_data/pg_hba.conf \
            -c ident_file=/pitr_data/pg_ident.conf \
            >> /tmp/pitr_recovery.log 2>&1
    "

    log "Waiting 20 seconds for recovery..."
    sleep 20

    log "Recovery logs:"
    docker exec pg-pitr-temp \
        bash -c "cat /tmp/pitr_recovery.log" | tee -a $LOG_FILE
}

verify_restore() {
    log "Verifying restored data..."

    docker exec pg-pitr-temp bash -c "
        gosu postgres psql \
            -p 5433 -U admin -d postgres \
            -c 'SELECT COUNT(*) AS restored_rows FROM employees;'
    " | tee -a $LOG_FILE

    log ""
    log "Connect to verify manually:"
    log "  docker exec pg-pitr-temp gosu postgres psql -p 5433 -U admin -d postgres"
    log ""
    log "When done, clean up:"
    log "  docker stop pg-pitr-temp && docker rm pg-pitr-temp"
}

# ── MAIN ──────────────────────────────────────────────────────
log "════════════════════════════════"
log "PITR Restore Started"
log "Target: $RECOVERY_TARGET_TIME"
log "════════════════════════════════"

confirm_restore
check_files_exist
stop_postgresql
clear_data_volume
restore_base_backup
copy_wal_archive
write_recovery_config
create_recovery_signal
start_recovery
verify_restore

log "════════════════════════════════"
log "PITR Restore Complete!"
log "Verify data then restart pg-node1"
log "════════════════════════════════"
