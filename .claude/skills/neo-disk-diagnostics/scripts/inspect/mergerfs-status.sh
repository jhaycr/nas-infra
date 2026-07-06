#!/usr/bin/env bash
# READ-ONLY: MergerFS pool health on neo — mounts, branch fill, options.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

section "MergerFS + branch mounts"
neo_shell "mount | grep -E 'mergerfs|/mnt/(storage|data|parity|cache)' || echo 'No mergerfs/branch mounts found (BAD).'"

section "Branch and pool fill levels"
neo_shell "df -h /mnt/storage /mnt/data* /mnt/parity* /mnt/cache* 2>/dev/null"

section "fstab storage entries"
neo_shell "grep -E 'mergerfs|/mnt/(data|parity|cache|storage)' /etc/fstab 2>/dev/null || true"

section "Recent mergerfs/fuse kernel messages"
neo_shell "dmesg -T 2>/dev/null | grep -iE 'mergerfs|fuse' | tail -10 || echo 'None.'"
