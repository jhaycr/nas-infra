---
name: neo-disk-diagnostics
description: Diagnose disk, SnapRAID, and MergerFS issues on the neo NAS. Use when SnapRAID sync/scrub fails, disks show SMART errors, the storage pool misbehaves, or the Grafana disk-health dashboard shows errors. Read-only inspection is safe to run; any change requires explicit user approval.
---

# Neo Disk Diagnostics

Diagnose storage issues on `neo` (192.168.1.3): SnapRAID sync/scrub failures, failing disks, MergerFS pool problems.

## SAFETY RULES (non-negotiable)

1. **Never damage data or disks.** Never run: `mkfs`, `dd`, `fdisk`, `parted`, `wipefs`, `cryptsetup luksFormat`, `snapraid fix`, `snapraid sync`, `rm` on `/mnt/*`, or any mount/umount of data disks.
2. **Read-only scripts** (`scripts/inspect/`) may be run freely without asking.
3. **Write scripts** (`scripts/remediate/`) are dry-run by default. Before running any of them with `--confirm`, you MUST:
   - Show the user the exact command, what it will do, and why.
   - Wait for the user's explicit approval in the conversation.
   - Never chain approval: one approval = one script execution.
4. If a situation isn't covered by an existing remediate script, do NOT improvise shell commands that modify neo. Present findings and a proposed plan to the user instead.
5. A failing disk is evidence — do not attempt "repairs" on it (no long SMART self-tests without asking, no badblocks, no secure erase).

## How to reach neo

All host access goes through Ansible ad-hoc from the repo root (`~/Code/ansible/nas-infra`). Direct `ssh neo` lands as `user0` who has **no passwordless sudo**; Ansible connects as user `ansible` with become:

```bash
cd ~/Code/ansible/nas-infra
ansible neo -m shell -a "<command>" --become
```

The inspection/remediation scripts wrap this — prefer them over raw ad-hoc commands.

## Architecture (neo storage)

- **Layers:** physical disks → LUKS (`/dev/mapper/crypt-*`) → SnapRAID (parity) → MergerFS union at `/mnt/storage`.
- **Data disks:** `/mnt/data1`–`/mnt/data5` (crypt-data1..5). **Parity:** `/mnt/parity1`, `/mnt/parity3`.
- **SnapRAID config:** `/etc/snapraid.conf`; content file `/var/snapraid.content`; lock file `/var/snapraid.content.lock`.
- **snapraid-runner:** `/opt/snapraid-runner/snapraid-runner.py` + `.conf`, logs to `/var/log/snapraid.log`, launched from **root's crontab** nightly at 01:00. Repo also ships `/opt/snapraid-arr-sync.sh` (pauses *Arr download clients around the run).
- **Ansible sources:** roles `jhaycr.snapraid` (install/config/cron) and `jhaycr-local.snapraid` (arr-sync wrapper); vars in `group_vars/neo/vars.yml` (`snapraid_*`).

## Observability

- **Grafana** (anonymous read OK): `http://192.168.1.3:3000/d/neo-disk-health-001/disk-health`
- **Loki** API: `http://192.168.1.3:3100` — snapraid logs under `{job="snapraid"}` (shipped by Alloy from `/var/log/snapraid.log`).
- **Prometheus** via Grafana proxy: `http://192.168.1.3:3000/api/datasources/proxy/uid/PBFA97CFB590B2093/api/v1/query?query=<promql>`
- Key log markers in snapraid logs: `Run finished successfully` / `All done` (success), `Run failed` (failure), `[OUTERR]` (snapraid stderr, e.g. "SnapRAID is already in use!", I/O errors).
- Dashboard template lives at `docker/neo/infra/metrics/appdata/metrics/config/dashboards/disk-health.json.j2`; deploy dashboard changes with `make neo-docker metrics`.

## Diagnostic workflow

Run these in order; each is read-only:

1. `scripts/inspect/snapraid-status.sh` — running/stuck snapraid processes, lock file, cron entry, last run result from the log.
2. `scripts/inspect/disk-health.sh` — SMART health for every disk, device→LUKS→mountpoint mapping, kernel I/O errors from dmesg.
3. `scripts/inspect/mergerfs-status.sh` — pool mount, branch fill levels, mount options.
4. `scripts/inspect/snapraid-logs.sh [days]` — success/failure timeline and error lines from Loki (default 30 days).

### Interpreting results

- **"SnapRAID is already in use!" / lock file held** → a previous run is stuck. Check process elapsed time (`ELAPSED` in snapraid-status output). A sync/scrub running for many days with low CPU time and low disk throughput is stalled, usually blocked retrying reads on a bad disk. Check dmesg/SMART next — the stall is a symptom, the disk is the cause.
- **SMART `FAILED` / high Reallocated or Pending sectors** → the disk needs replacement. Identify its role (data vs parity) from the lsblk mapping. A dead *parity* disk means no data loss but reduced protection; a dead *data* disk means files on it are at risk and recoverable via `snapraid fix` **only with user driving the process**.
- **Scrub exit status 1 at random times** → usually I/O errors during scrub; correlate timestamps with dmesg errors.
- **Cron drift** — compare root's live crontab against `snapraid_runner_cron_jobs` in `group_vars/neo/vars.yml`. Redeploying is `make neo-disks` (requires user approval; it touches disk-related roles).

## Remediation (user approval required for each)

- `scripts/remediate/kill-stuck-snapraid.sh` — terminate a stuck snapraid-runner/scrub process tree. Dry-run by default; `--confirm` to execute. Killing a **scrub** is safe (scrub only reads). Killing a **sync** is crash-safe by SnapRAID's design but the script requires an extra `--allow-sync` flag and you must warn the user.
- `scripts/remediate/remove-stale-lock.sh` — remove `/var/snapraid.content.lock` only when no snapraid process is running. Dry-run by default; `--confirm` to execute. (Usually unnecessary — snapraid uses flock, so the lock releases when the process dies.)
- `scripts/remediate/snapraid-cron.sh disable|enable` — comment/uncomment the nightly snapraid_runner cron entry (e.g. while waiting for a disk replacement). Dry-run by default; `--confirm` to execute.

Anything beyond these (disk replacement, `snapraid sync`/`fix`, config changes, redeploying Ansible roles) → write up a step-by-step plan and hand it to the user. Do not execute it yourself.

## Reporting

End every diagnostic session with a summary: what's broken, root cause, evidence (log lines, SMART values, timestamps), and a recommended plan split into (a) actions you can take with approval and (b) actions only the user can take (physical swaps, purchases).
