#!/bin/bash
#==============================================================
# PostgreSQL pg_basebackup Automated Backup Script
# Purpose: Take physical backup of entire PostgreSQL server
# Schedule: Run via CRON every Sunday at midnight
# Cron entry: 0 0 * * 0 /path/to/cron-backup.sh
#==============================================================

set -e

#--------------------------------------------------------------
# CONFIGURATION
#--------------------------------------------------------------
CONTAINER_NAME="pg-node1"
PG_USER="replicator"        # Must use replication user!
PG_PASSWORD="Repl@1234"

# Backup destination
BACKUP_DIR="/tmp/pg_physical_backups"

# How many weeks to keep backups
RETENTION_DAYS=30           # Keep last 30 days

# Log file
LOG_FILE="/tmp/pg_basebackup.log"

#--------------------------------------------------------------
# FUNCTIONS
#--------------------------------------------------------------

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

check_replication_user() {
    # Verify replicator user exists and has correct privileges
    local RESULT=$(docker exec $CONTAINER_NAME \
        psql -U admin -d postgres -tAc \
        "SELECT count(*) FROM pg_roles
         WHERE rolname='replicator' AND rolreplication=true;")

    if [ "$RESULT" != "1" ]; then
        log "ERROR: replicator user missing or no REPLICATION privilege!"
        exit 1
    fi
    log "Replication user verified OK"
}

take_physical_backup() {
    local DATE=$(date +%Y%m%d_%H%M%S)
    local BACKUP_PATH="$BACKUP_DIR/backup_${DATE}"

    log "Starting pg_basebackup..."
    log "Destination: $BACKUP_PATH"

    # Create backup directory
    mkdir -p $BACKUP_PATH

    # Run pg_basebackup inside container
    docker exec $CONTAINER_NAME \
        pg_basebackup \
        -h localhost \
        -p 5432 \
        -U $PG_USER \
        -D /tmp/physical_backup_${DATE} \
        -F t \
        -z \
        -P \
        -v \
        --wal-method=stream

    # Copy backup from container to Mac
    docker cp \
        $CONTAINER_NAME:/tmp/physical_backup_${DATE} \
        $BACKUP_PATH/

    # Remove temp backup from container
    docker exec $CONTAINER_NAME \
        rm -rf /tmp/physical_backup_${DATE}

    # Verify backup files exist
    if [ -f "$BACKUP_PATH/physical_backup_${DATE}/base.tar.gz" ]; then
        local SIZE=$(du -sh $BACKUP_PATH | cut -f1)
        log "SUCCESS: Physical backup → $BACKUP_PATH ($SIZE)"
        log "Files:"
        ls -lh $BACKUP_PATH/physical_backup_${DATE}/ | tee -a $LOG_FILE
    else
        log "ERROR: Physical backup failed — base.tar.gz missing!"
        exit 1
    fi
}

verify_backup() {
    log "Verifying backup integrity..."

    # Check backup_manifest exists
    local LATEST=$(ls -td $BACKUP_DIR/backup_*/ 2>/dev/null | head -1)

    if [ -z "$LATEST" ]; then
        log "ERROR: No backup found to verify!"
        exit 1
    fi

    local MANIFEST="$LATEST/physical_backup_*/backup_manifest"
    if ls $MANIFEST 2>/dev/null | head -1 | grep -q "backup_manifest"; then
        log "SUCCESS: backup_manifest found — backup is valid"
    else
        log "WARNING: backup_manifest not found"
    fi
}

delete_old_backups() {
    log "Deleting backups older than $RETENTION_DAYS days..."
    local COUNT=$(find $BACKUP_DIR \
        -maxdepth 1 \
        -name "backup_*" \
        -type d \
        -mtime +$RETENTION_DAYS | wc -l)
    find $BACKUP_DIR \
        -maxdepth 1 \
        -name "backup_*" \
        -type d \
        -mtime +$RETENTION_DAYS \
        -exec rm -rf {} \;
    log "Deleted $COUNT old backup directories"
}

show_backup_summary() {
    log "============ BACKUP SUMMARY ============"
    log "Backup directory: $BACKUP_DIR"
    log "Available backups:"
    ls -lhd $BACKUP_DIR/backup_*/ 2>/dev/null | tee -a $LOG_FILE
    log "Total size: $(du -sh $BACKUP_DIR | cut -f1)"
    log "========================================"
}

#--------------------------------------------------------------
# MAIN
#--------------------------------------------------------------

log "========================================"
log "PostgreSQL Physical Backup Started"
log "========================================"

mkdir -p $BACKUP_DIR

check_postgres_running
check_replication_user
take_physical_backup
verify_backup
delete_old_backups
show_backup_summary

log "========================================"
log "Physical Backup Completed Successfully"
log "========================================"

#--------------------------------------------------------------
# HOW TO SETUP CRON
#--------------------------------------------------------------
# chmod +x cron-backup.sh
# crontab -e
# Add: 0 0 * * 0 /path/to/cron-backup.sh
# This runs every Sunday at midnight
#
# IN PRODUCTION: Upload to S3 after backup:
# aws s3 sync $BACKUP_PATH s3://my-bucket/physical-backups/
#--------------------------------------------------------------
