#!/bin/bash
#==============================================================
# pg_dump Automated Backup Script
# Cron: 0 2 * * * /path/to/backup.sh >> /tmp/pg_backup.log 2>&1
#==============================================================

set -e

# ── CONFIGURATION ─────────────────────────────────────────────
CONTAINER_NAME="pg-node1"
PG_USER="admin"
BACKUP_DIR="/tmp/pg_logical_backups"
RETENTION_DAYS=7
DATABASES="postgres"
LOG_FILE="/tmp/pg_backup.log"
# ──────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

check_postgres_running() {
    if ! docker ps | grep -q $CONTAINER_NAME; then
        log "ERROR: Container $CONTAINER_NAME not running!"
        exit 1
    fi
    log "Container $CONTAINER_NAME is running OK"
}

create_backup_dir() {
    mkdir -p $BACKUP_DIR
    log "Backup directory: $BACKUP_DIR"
}

backup_database() {
    local DB=$1
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$BACKUP_DIR/${DB}_${DATE}.dump"

    log "Starting backup: $DB"

    docker exec $CONTAINER_NAME pg_dump \
        -U $PG_USER -d $DB -F c \
        -f /tmp/${DB}_${DATE}.dump

    docker cp $CONTAINER_NAME:/tmp/${DB}_${DATE}.dump \
        $BACKUP_FILE

    docker exec $CONTAINER_NAME \
        rm -f /tmp/${DB}_${DATE}.dump

    if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
        local SIZE=$(du -sh $BACKUP_FILE | cut -f1)
        log "SUCCESS: $DB → $BACKUP_FILE ($SIZE)"
    else
        log "ERROR: Backup failed for $DB"
        exit 1
    fi
}

backup_all_databases() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_FILE="$BACKUP_DIR/all_databases_${DATE}.sql"

    log "Starting pg_dumpall..."

    docker exec $CONTAINER_NAME pg_dumpall \
        -U $PG_USER -f /tmp/all_databases_${DATE}.sql

    docker cp $CONTAINER_NAME:/tmp/all_databases_${DATE}.sql \
        $BACKUP_FILE

    docker exec $CONTAINER_NAME \
        rm -f /tmp/all_databases_${DATE}.sql

    if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
        local SIZE=$(du -sh $BACKUP_FILE | cut -f1)
        log "SUCCESS: All databases → $BACKUP_FILE ($SIZE)"
    else
        log "ERROR: pg_dumpall failed!"
        exit 1
    fi
}

delete_old_backups() {
    log "Deleting backups older than $RETENTION_DAYS days..."
    local COUNT=$(find $BACKUP_DIR \
        \( -name "*.dump" -o -name "*.sql" \) \
        -mtime +$RETENTION_DAYS | wc -l)
    find $BACKUP_DIR \
        \( -name "*.dump" -o -name "*.sql" \) \
        -mtime +$RETENTION_DAYS -delete
    log "Deleted $COUNT old files"
}

show_summary() {
    log "──── BACKUP SUMMARY ────"
    ls -lh $BACKUP_DIR | tee -a $LOG_FILE
    log "Total: $(du -sh $BACKUP_DIR | cut -f1)"
    log "────────────────────────"
}

# ── MAIN ──────────────────────────────────────────────────────
log "════════════════════════════════"
log "pg_dump Backup Started"
log "════════════════════════════════"

check_postgres_running
create_backup_dir

for DB in $DATABASES; do
    backup_database $DB
done

backup_all_databases
delete_old_backups
show_summary

log "════════════════════════════════"
log "pg_dump Backup Completed OK"
log "════════════════════════════════"
