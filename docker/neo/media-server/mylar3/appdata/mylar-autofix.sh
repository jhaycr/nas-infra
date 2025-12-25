#!/bin/bash

DB="/config/mylar/mylar.db"
LOG="/config/mylar/logs/mylar.log"
LOCK_THRESHOLD=5

LOCKS=$(grep -c "database is locked" "$LOG")

# Exit if not enough errors to justify intervention
[ "$LOCKS" -lt "$LOCK_THRESHOLD" ] && exit 0

echo "[AUTOHEAL] Detected persistent SQLite lock, attempting recovery..."

sqlite3 "$DB" <<EOF
-- Clear stuck scheduler jobs
DELETE FROM jobhistory;

-- Reset DDL jobs stuck mid-flight
UPDATE ddl_info SET status = 'Waiting' WHERE status != 'Completed';

-- Clear noisy notifications
DELETE FROM notifs;

-- Force conservative locking
PRAGMA journal_mode=DELETE;
PRAGMA synchronous=FULL;
PRAGMA locking_mode=EXCLUSIVE;
VACUUM;
EOF

echo "[AUTOHEAL] SQLite recovery attempt complete"
