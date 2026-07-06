#!/usr/bin/env bash
# WRITE TOOL — requires explicit user approval before running with --confirm.
#
# Disables/enables the nightly snapraid_runner cron entry in root's crontab on neo.
# Useful while a failing disk awaits replacement (avoids nightly failure noise/alerts).
# Dry-run by default.
#
#   snapraid-cron.sh disable            # dry run
#   snapraid-cron.sh disable --confirm  # comment out the cron entry
#   snapraid-cron.sh enable --confirm   # uncomment it
#
# Note: the cron entry is Ansible-managed ("#Ansible: snapraid_runner"); a later
# `make neo` / `make neo-disks` run will re-enable it. Mention this to the user.
source "$(dirname "${BASH_SOURCE[0]}")/../inspect/_lib.sh"

ACTION="${1:-}"
CONFIRM=false
[ "${2:-}" = "--confirm" ] && CONFIRM=true

if [[ "$ACTION" != "disable" && "$ACTION" != "enable" ]]; then
  echo "Usage: $0 disable|enable [--confirm]" >&2
  exit 2
fi

section "Current root crontab (snapraid entries)"
neo_shell "crontab -l 2>/dev/null | grep -B1 -A1 -i snapraid_runner || echo 'No snapraid_runner entry found.'"

if ! $CONFIRM; then
  echo
  echo "DRY RUN. Would ${ACTION} the line following '#Ansible: snapraid_runner'."
  echo "Re-run with '${ACTION} --confirm' AFTER the user has approved."
  exit 0
fi

if [ "$ACTION" = "disable" ]; then
  # Comment out the job line that follows the Ansible marker, if not already commented.
  neo_shell "crontab -l | awk 'prev==\"#Ansible: snapraid_runner\" && \$0 !~ /^#/ {print \"#DISABLED#\" \$0; prev=\$0; next} {print; prev=\$0}' | crontab - && echo OK"
else
  neo_shell "crontab -l | sed 's/^#DISABLED#//' | crontab - && echo OK"
fi

section "Resulting crontab (snapraid entries)"
neo_shell "crontab -l 2>/dev/null | grep -B1 -A1 -i snapraid_runner"
