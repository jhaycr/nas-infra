#!/usr/bin/env bash
# READ-ONLY: SnapRAID runner state on neo — processes, lock file, cron, last run result.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

section "SnapRAID / runner processes (watch ELAPSED vs TIME: days elapsed + tiny CPU = stalled)"
neo_shell "ps -eo pid,ppid,stat,etime,time,args | grep -iE 'snapraid' | grep -v grep || echo 'No snapraid processes running.'"

section "Lock file (/var/snapraid.content.lock)"
neo_shell "ls -la /var/snapraid.content.lock 2>/dev/null || echo 'No lock file present.'"

section "Root crontab (snapraid entries)"
neo_shell "crontab -l 2>/dev/null | grep -iB1 snap || echo 'No snapraid cron entries.'"

section "Expected cron (repo: group_vars/neo/vars.yml snapraid_runner_cron_jobs)"
grep -A3 "snapraid_runner_cron_jobs" "$REPO_ROOT/group_vars/neo/vars.yml"

section "Last 25 lines of /var/log/snapraid.log"
neo_shell "tail -25 /var/log/snapraid.log 2>/dev/null || echo 'No log file.'"

section "Last success and last failure in log"
neo_shell "grep 'Run finished successfully' /var/log/snapraid.log 2>/dev/null | tail -1; grep -E 'Run failed\$' /var/log/snapraid.log 2>/dev/null | tail -1"
