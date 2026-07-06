---
name: ha-control
description: Read and write the Home Assistant instance (oracle / HA Green, 192.168.1.152). Use for ANY interaction with HA — status, logs, entity lookup, config pushes, add-on changes, restarts. Inspect scripts are read-only and safe; every write script takes a Supervisor backup first and requires user approval. Direct ssh/ansible writes to oracle are blocked by a PreToolUse hook — this skill is the only sanctioned write path.
---

# HA Control (oracle / HA Green)

Backup-gated tooling for the Home Assistant instance. Context docs live in the
private submodule: `files/home_assistant/CLAUDE.md` and `files/home_assistant/docs/`.

## SAFETY RULES (non-negotiable)

1. **Every write goes through `scripts/write/*`** — never raw `ssh`/`scp`/`ansible`
   against 192.168.1.152 for anything that mutates state. A PreToolUse hook
   (`.claude/hooks/ha-write-gate.py`) blocks direct write commands; do not try
   to evade it.
2. **Write scripts are dry-run by default.** Run the dry run, show the user the
   plan, get explicit approval, then re-run with `--confirm`.
3. **Backups are mandatory and automatic** — `--confirm` takes a Supervisor
   backup before acting and aborts the write if the backup fails. Never skip it.
4. **Backup scope:** partial (HA config + DB) by default; pass `--full` to
   `ha-exec.sh` when the change touches add-ons or their data (Z2M, Z-Wave JS,
   Mosquitto, `/addon_configs`, `ha addons ...`).
5. Never edit `/config/.storage/`, never read vault files, never pull/commit
   `secrets.yaml` (see `files/home_assistant/CLAUDE.md`).

## Inspect (read-only, safe to run without asking)

| Script | Purpose |
|---|---|
| `scripts/inspect/status.sh` | Core/OS/add-on versions & state, supervisor issues, recent backups |
| `scripts/inspect/logs.sh [core\|z2m\|zwave\|mosquitto\|matter\|otbr] [lines]` | Tail logs |
| `scripts/inspect/find.sh <pattern>` | Search entity/device/area registries |
| `scripts/inspect/run-ro.sh '<cmd>'` | Arbitrary read-only remote command (refuses write patterns) |

## Write (user approval required for each `--confirm`)

| Script | Backup | Purpose |
|---|---|---|
| `scripts/write/backup.sh [--full]` | is one | Manual backup + prune (keeps newest 5 per auto-prefix) |
| `scripts/write/push-config.sh [--confirm]` | partial, via site.yml pre_task | Diff & push managed YAML (`files/home_assistant/`) via `make oracle-push`; restarts HA only if changed |
| `scripts/write/ha-exec.sh [--confirm] [--full] '<cmd>'` | partial or full | Any other mutation (add-on options, /config file surgery) |
| `scripts/write/restart.sh [--confirm]` | partial | Restart HA core, wait for healthy |

## Typical workflows

**Change an automation/scene/dashboard:**
1. `make oracle-pull` + diff — make sure the repo matches live (UI edits land in the same files).
2. Edit YAML in `files/home_assistant/`.
3. `scripts/write/push-config.sh` (dry run) → show user → `--confirm`.
4. Commit in the submodule, bump pointer in nas-infra.

**Reload without restart** (scenes/scripts/automations): after a push, prefer
`run-ro.sh` is not applicable (it's a POST) — ask the user to reload via UI, or
use `ha-exec.sh` only if a restart is undesirable and the user approves.

**Emergency escape hatch:** `make oracle-push EXTRA_VARS="ha_skip_backup=true"`
skips the pre-push backup (e.g. when backup storage itself is the problem).
Only with explicit user instruction.

## Restore

Backups are Supervisor backups on the box. List: `inspect/status.sh`. Restore is
intentionally NOT scripted — walk the user through Settings → System → Backups,
or `ha backups restore <slug>` via `ha-exec.sh` with user approval.
