# Hermes runbook — launching it and getting real work out of it

Hermes is the autonomous agent on **smith** (NixOS VM on neo, `192.168.1.61`).
It holds git clones of the infra repos in `/workspace` and authors changes
there; it has **no write access to any live system**. You review and deploy.

Deeper references: `nix/smith/HERMES-WORKFLOW.md` (HA pipeline details,
secrets inventory), `nix/smith/workspace-README.md` (the agent-side command
sheet deployed to `/workspace/README.md`), `nix/smith/README.md` (VM bring-up).

## Launching Hermes

| How | Command / URL | Use for |
|---|---|---|
| Interactive chat (terminal) | `hermes` (alias in `~/.bashrc` → ssh to smith, `hermes chat`) | back-and-forth sessions |
| One-shot task | `hermes-run "task text"` (alias → `hermes -z`) | fire-and-forget; can take minutes |
| Dashboard chat | <http://192.168.1.61:9119> — basic auth `josh` + vault `secret_hermes_josh_dashboard_password` | chat from any browser, watch sessions |
| From Claude Code | `.claude/skills/hermes-agent/` (`scripts/run.sh "task"`) | delegating from a Claude session |
| API | `http://192.168.1.61:8642/v1` (OpenAI-compatible; Bearer = vault `secret_hermes_josh_api_server_key`, model `hermes-agent`) | scripting/integrations |

Watching it work: dev HA instance renders at <http://192.168.1.61:8124>
(login `hermes` + vault `secret_hermes_josh_ha_dev_password`); logs in
Grafana/Loki with `{instance="smith"}`.

## What it can and can't do

- `/workspace/nas-infra` — clone of this repo, **pull-only** (no deploy key
  yet). It can author and commit locally on `hermes/<topic>` branches but
  cannot push them to GitHub.
- `/workspace/home-assistant-config` — private HA repo, **push allowed** for
  `hermes/<topic>` branches via deploy key. Never main, never force-push.
- No `gh` CLI or GitHub token: it cannot open PRs or read issues — it hands
  you ready-to-paste PR text instead.
- Live systems (oracle, neo, trinity, morpheus): read-only at most. All
  deploys run from trinity, by you.

## Runbook: a basic NAS change (nas-infra)

Example goals: bump an image tag, add a Docker service, tweak a role.

1. **Task it**, naming the clone and the branch convention:
   ```
   hermes-run "In /workspace/nas-infra: pull latest main, then add a
   <service> compose service under docker/neo/<stack>/ following the
   existing patterns (see AGENTS.md). Commit on branch hermes/<topic>.
   Pick a free port from docs/ports.md. Do not touch vault files."
   ```
2. **Fetch its branch** — it can't push, but trinity can read smith's clone
   over ssh. From your nas-infra checkout:
   ```bash
   git fetch ssh://ansible@192.168.1.61/var/lib/hermes-workspace/nas-infra \
       hermes/<topic>:hermes/<topic>
   git diff main...hermes/<topic>
   ```
3. **Review, merge, push** to GitHub as usual.
4. **Deploy** with the matching target: `make neo-docker` (compose),
   `make neo` (roles), `make smith`, `make trinity`, etc.
5. **Verify**: for container changes, check logs via Dozzle —
   `http://192.168.1.3:8081`.

## Runbook: an HA addition (e.g. a new dashboard)

Hermes proves HA changes on its own dev instance before you ever touch
oracle. Full pipeline detail: `nix/smith/HERMES-WORKFLOW.md`.

1. **Task it**:
   ```
   hermes-run "Add a <name> dashboard to home-assistant-config showing
   <what>. Use real entity ids from the live box. Test it on the dev HA
   instance, push branch hermes/<topic>, and give me the PR title/body
   with your test evidence."
   ```
2. **Watch** (optional) at <http://192.168.1.61:8124> — dashboards under
   test render there with seeded fake entities.
3. **Open the PR** at `github.com/jhaycr/home-assistant-config` using the
   text Hermes hands back. Reject if there's no test evidence. Check: no
   edits to automations it didn't create, no secrets/credentials, new
   dashboard files have their `lovelace:` entry in `configuration.yaml`.
4. **Dashboard-specific**: add the new filename to
   `hass_control_config_files` in `group_vars/oracle/vars.yml` (this repo),
   or the push role won't manage it.
5. **Merge and deploy** from trinity:
   ```bash
   git -C files/home_assistant checkout main && git -C files/home_assistant pull
   bash .claude/skills/ha-control/scripts/write/push-config.sh           # dry-run diff
   bash .claude/skills/ha-control/scripts/write/push-config.sh --confirm # backup + push
   git add files/home_assistant && git commit -m "Bump HA submodule"
   ```
   A partial Supervisor backup is taken automatically before every push;
   rollback via Settings → System → Backups (`pre-push-*`).

## Troubleshooting

- **`hermes` CLI dies with `PermissionError ... /opt/data/.env`** — the
  image's shim drops root→uid 10000; everything it touches must be owned
  `10000:10000`. Enforced by tmpfiles rules in `nix/smith/configuration.nix`;
  re-run `make smith` if it regresses.
- **Restart the agent**: `ssh ansible@192.168.1.61 sudo systemctl restart
  podman-hermes-josh` (also required after changing any `/etc/hermes/*.env`
  secret — a rebuild alone won't restart it on content-only changes).
- **Secrets** (API keys, passwords): edit `group_vars/smith/vault.yml` via
  `make vault-unlock`/`vault-lock`, then `make smith`. Inventory of every
  vault var: `nix/smith/HERMES-WORKFLOW.md`.
- **Spend**: LLM calls route through the OpenRouter key — keep a credit
  limit set on the key at openrouter.ai before long unattended runs.
