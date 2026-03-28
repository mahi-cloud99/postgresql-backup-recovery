#!/bin/bash

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backups"
mkdir -p $BACKUP_DIR

echo "Starting backup at $DATE"

# Backup each database
for DB in postgres appdb; do
    echo "Backing up $DB..."
    pg_dump -U admin -d $DB -F c \
        -f "$BACKUP_DIR/${DB}_${DATE}.dump"
    echo "Done: ${DB}_${DATE}.dump"
done

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.dump" -mtime +7 -delete
echo "Old backups cleaned up"

echo "Backup complete!"
ls -lh $BACKUP_DIR
