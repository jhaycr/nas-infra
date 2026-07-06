#!/usr/bin/env bash
# READ-ONLY: SMART health of all neo disks, device->LUKS->mount mapping, kernel I/O errors.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

section "Block device -> LUKS -> mountpoint mapping"
neo_shell "lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINT"

section "SMART health summary (all disks)"
neo_shell '
for d in /dev/sd? /dev/nvme0n1; do
  [ -e "$d" ] || continue
  echo "--- $d ---"
  smartctl -H -A "$d" 2>/dev/null | grep -E "result|Reallocated_Sector|Current_Pending|Offline_Uncorrect|Reported_Uncorrect|UDMA_CRC|Media_Wearout|Percentage Used|Temperature_Cel" || echo "  (no SMART data)"
done'

section "Kernel disk errors (dmesg, last 20)"
neo_shell "dmesg -T 2>/dev/null | grep -iE 'i/o error|ata[0-9]+.*error|blk_update|critical (medium|target)|unrecovered read' | tail -20 || echo 'No recent kernel disk errors.'"

section "Per-device dmesg error counts"
neo_shell "dmesg -T 2>/dev/null | grep -oE 'dev sd[a-z]+' | sort | uniq -c | sort -rn || true"
