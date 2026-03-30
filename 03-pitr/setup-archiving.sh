#!/bin/bash
#==============================================================
# PITR WAL Archiving Setup Script
# Run ONCE to enable WAL archiving on primary
# NOT a cron job — run manually to set up
# Usage: bash setup-archiving.sh
#==============================================================

set -e

# ── CONFIGURATION ─────────────────────────────────────────────
CONTAINER_NAME="pg-node1"
CLUSTER_NAME="pg-cluster"
ARCHIVE_DIR="/var/lib/postgresql/wal_archive"
BACKUP_DIR="/tmp/pitr_backups"
LOG_FILE="/tmp/pitr_setup.log"
# ──────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

create_archive_directory() {
    log "Creating WAL archive directory..."
    docker exec $CONTAINER_NAME bash -c "
        mkdir -p $ARCHIVE_DIR &&
        chown postgres:postgres $ARCHIVE_DIR &&
        chmod 700 $ARCHIVE_DIR &&
        echo 'Archive directory ready!'
    "
    log "Archive dir: $ARCHIVE_DIR"
}

enable_wal_archiving() {
    log "Enabling WAL archiving..."

    docker exec $CONTAINER_NAME \
        psql -U admin -d postgres \
        -c "ALTER SYSTEM SET archive_mode = 'on';"
    log "archive_mode = on"

    docker exec $CONTAINER_NAME \
        psql -U admin -d postgres \
        -c "ALTER SYSTEM SET archive_command = \
            'cp %p $ARCHIVE_DIR/%f';"
    log "archive_command configured"

    docker exec $CONTAINER_NAME \
        psql -U admin -d postgres \
        -c "ALTER SYSTEM SET archive_timeout = '60';"
    log "archive_timeout = 60 seconds"
}

restart_postgresql() {
    log "Restarting PostgreSQL to apply settings..."
    docker exec $CONTAINER_NAME \
        patronictl -c /etc/patroni.yml \
        restart $CLUSTER_NAME $CONTAINER_NAME --force
    log "Waiting 15 seconds..."
    sleep 15
}

verify_archiving() {
    log "Verifying archiving is active..."

    local MODE=$(docker exec $CONTAINER_NAME \
        psql -U admin -d postgres -tAc \
        "SELECT setting FROM pg_settings
         WHERE name = 'archive_mode';")

    if [ "$MODE" = "on" ]; then
        log "SUCCESS: archive_mode = on"
    else
        log "ERROR: archive_mode is not on!"
        exit 1
    fi

    log "Current archive settings:"
    docker exec $CONTAINER_NAME \
        psql -U admin -d postgres \
        -c "SELECT name, setting FROM pg_settings
            WHERE name IN
            ('archive_mode','archive_command','archive_timeout');"
}

take_base_backup() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_PATH="$BACKUP_DIR/pitr_base_${DATE}"

    log "Taking base backup for PITR..."
    mkdir -p $BACKUP_DIR

    docker exec $CONTAINER_NAME pg_basebackup \
        -h localhost -p 5432 \
        -U replicator \
        -D /tmp/pitr_base_${DATE} \
        -F t -z -P -v \
        --wal-method=stream

    docker cp \
        $CONTAINER_NAME:/tmp/pitr_base_${DATE} \
        $BACKUP_PATH

    docker exec $CONTAINER_NAME \
        rm -rf /tmp/pitr_base_${DATE}

    log "Base backup saved: $BACKUP_PATH"
    log "Copy to safe location:"
    log "  cp -r $BACKUP_PATH ~/Desktop/pg-backups/pitr/"
}

# ── MAIN ──────────────────────────────────────────────────────
log "════════════════════════════════"
log "PITR Archiving Setup"
log "════════════════════════════════"

create_archive_directory
enable_wal_archiving
restart_postgresql
verify_archiving
take_base_backup

log "════════════════════════════════"
log "PITR Setup Complete!"
log ""
log "WAL files will archive to: $ARCHIVE_DIR"
log "Base backup at: $BACKUP_DIR"
log ""
log "Next: run restore.sh when disaster happens"
log "════════════════════════════════"
