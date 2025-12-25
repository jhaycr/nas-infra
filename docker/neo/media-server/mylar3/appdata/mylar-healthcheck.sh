#!/bin/bash

DB="/config/mylar/mylar.db"
LOG="/config/mylar/logs/mylar.log"

# If DB missing, container is unhealthy
[ ! -f "$DB" ] && exit 1

# Check for persistent DB lock in recent logs
LOCKS=$(grep -c "database is locked" "$LOG")

# Healthy if no locks
[ "$LOCKS" -eq 0 ] && exit 0

# If locks exist, unhealthy
exit 1
