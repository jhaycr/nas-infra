# Hermes HA pipeline — Josh's runbook

How to use smith's Hermes agent to build Home Assistant changes safely.
The agent-side rules live on smith at `/var/lib/hermes-workspace/WORKFLOW.md`;
this doc is the human side: secrets, day-to-day flow, and maintenance.

## The pipeline at a glance

```
you give a goal → Hermes branches the private HA repo → proves it on the
dev HA instance (smith:8124) → pushes hermes/<topic> + PR with evidence
→ YOU review & merge → YOU deploy via gated oracle-push → verify on oracle
```

Hermes has **no write access to oracle or any live system** — only to git
branches and its own dev instance. Deploys always run from trinity with the
automatic pre-push Supervisor backup.

## Secrets inventory (`group_vars/smith/vault.yml`)

| Vault var | What | Where you get it |
|---|---|---|
| `secret_hermes_josh_openrouter_api_key` | LLM routing (MiniMax/Qwen/etc.) | openrouter.ai → Keys. **Set a credit limit on the key** (edit key → credit limit) before unattended runs |
| `secret_hermes_josh_openai_api_key` | OpenAI models | platform.openai.com → API keys. Set a monthly budget: Settings → Limits |
| `secret_hermes_josh_anthropic_api_key` | Anthropic models (EMPTY as of 2026-07) | console.anthropic.com → API keys; workspace spend limit in Settings → Limits |
| `secret_hermes_josh_api_server_key` | Bearer auth for Hermes API :8642 | generated (`openssl rand -hex 32`) |
| `secret_hermes_josh_dashboard_password` / `_hash` | Hermes dashboard :9119 basic auth | chosen + scrypt hash |
| `secret_hermes_josh_ha_deploy_key` | SSH deploy key, read-write, for private `jhaycr/home-assistant-config` | already installed (GitHub repo → Settings → Deploy keys → "hermes@smith"). Rotate: generate new keypair, replace on GitHub + in vault, `make smith` |
| `secret_hermes_josh_ha_dev_password` | Dev HA (:8124) owner login `hermes` — you use it in the web UI too | generated during bring-up; in vault |
| `secret_hermes_josh_ha_live_token` | **TODO — read-only live context.** Long-lived token from a NON-ADMIN HA user on oracle | see next section |

Edit flow for any of these: `make vault-unlock` → edit
`group_vars/smith/vault.yml` → `make vault-lock` → `make smith` (re-renders
`/etc/hermes/*.env` and rebuilds).

## One-time: create the read-only live-HA token

This lets Hermes read real entity ids/states/areas from oracle to seed its
dev instance. Non-admin = it cannot touch config, automations, or add-ons.

1. Oracle web UI (`http://homeassistant.local:8123`) → **Settings → People →
   Users → Add user**. Name/username `hermes-ro`, strong password,
   **leave "Administrator" OFF**, allow login.
2. Log in as `hermes-ro` (private/incognito window) → click the user avatar
   (bottom-left) → **Security** tab → **Long-lived access tokens → Create
   token**. Copy it — HA shows it once. (Tokens are per-user; it must be
   created while logged in AS `hermes-ro`.)
3. Add it to the vault as `secret_hermes_josh_ha_live_token`, then
   `make smith`. The env slot (`HA_LIVE_URL`/`HA_LIVE_TOKEN` in
   `/etc/hermes/ha-dev.env`) is already wired.
4. Revoke any time: log in as `hermes-ro` → Security → delete the token
   (or delete the whole user).

Caveat: non-admin users can still *call services* (turn lights on). The
agent's rules say read-only; the hard guarantee is only "no config/admin
writes". Acceptable for a LAN agent — revoke if it misbehaves.

## Day-to-day flow

1. **Give Hermes a goal** — dashboard chat `http://192.168.1.61:9119`, the
   `hermes` alias from your laptop, or the API (:8642).
2. **It works autonomously**: branch → edit YAML → deploy to dev HA → seed
   states → verify → push `hermes/<topic>`. Watch the dev instance live at
   `http://192.168.1.61:8124` (login `hermes` + vault
   `secret_hermes_josh_ha_dev_password`) — dashboards under test render
   there with seeded fake entities.
3. **Review the PR** on `github.com/jhaycr/home-assistant-config`. Expect
   test evidence in the body; reject without it. Check for: edits to
   entries it didn't create in `automations.yaml`, any `secrets.yaml` or
   credential material (never allowed), new dashboard files missing their
   `lovelace:` entry.
4. If the PR adds a dashboard file: also add the filename to
   `hass_control_config_files` in `group_vars/oracle/vars.yml` (nas-infra).
   If it references new `!secret` names: add them to `secrets.yaml` on
   oracle (via the gated push flow, or the UI file editor).
5. **Merge**, then deploy from trinity:
   ```
   cd ~/Code/ansible/nas-infra
   git -C files/home_assistant checkout main && git -C files/home_assistant pull
   bash .claude/skills/ha-control/scripts/write/push-config.sh          # dry-run diff
   bash .claude/skills/ha-control/scripts/write/push-config.sh --confirm # backup + push
   git add files/home_assistant && git commit -m "Bump HA submodule"     # pointer bump
   ```
6. **Verify on oracle** (UI or ha-control inspect scripts). Rollback if
   needed: Settings → System → Backups → `pre-push-*`.

## Dev instance maintenance

- Reset to blank slate + reprovision: see "Dev HA instance" in `BRINGUP.md`.
- Version: `ha-dev` image tag in `configuration.nix` is pinned to oracle's
  Core version — when you upgrade the Green, bump the tag and `make smith`.
- The dev `configuration.yaml` is a disposable test fixture. Nothing in
  `/var/lib/ha-dev` is precious.

## Not built yet (phase 3)

Smith-triggered deploys: a Semaphore template wrapping oracle-push that
Hermes can fire, with a pre_task that verifies the deployed commit came
through a PR **approved by you** (GitHub API check) — so the agent controls
*when*, never *what*. Until then, deploys are manual (step 5 above).
