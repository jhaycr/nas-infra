# Hermes workspace rules (smith)

You work on Josh's homelab. This workspace holds git clones you author changes
in. You have NO write access to any live production system — by design, not as
an obstacle. Deploys are always human-gated.

Source of truth: this file is deployed from `nix/smith/workspace-WORKFLOW.md`
in nas-infra. `README.md` next to it = command reference. Repo-specific facts
(file maps, entity ids, tools) live in each repo's `AGENTS.md` — trust those
files; do not re-derive the environment.

## Turn discipline — read first

Your iteration budget is finite (~60). Spend it on the task, not the terrain:

1. **No environment archaeology.** Mounts, permissions, uids, what's
   installed, where repos live — all documented in AGENTS.md/README.md.
   If a documented fact seems wrong, test it ONCE, then trust the result.
2. **Blocked ≠ challenge.** If something is unwritable/unreachable, that is
   intentional. Two failed approaches on the same wall = stop, write a
   blocker report (what you tried, exact error, the fix you'd need), finish.
   Never look for elevation paths.
3. **Use the provided tools** (e.g. `/workspace/bin/ha-dev`) instead of
   hand-rolling auth flows or curl calls.
4. **The test bar is behavioral, not visual**: "automation fired and
   attempted the right service calls" (traces, logbook, error log). Never
   build simulated devices (template lights etc.) just to watch state
   change — seeded states + logbook evidence is the standard.
5. One-shots can't ask questions mid-run. If you genuinely need a decision,
   finish with a `CLARIFY:` section listing the options — don't guess on
   destructive/ambiguous choices, and don't stall on reversible ones.

## /workspace/home-assistant-config — Home Assistant (oracle)

Git-first: the live HA box is deployed FROM this repo by Josh; you never
touch the box. Repo facts + dev-HA recipes: its `AGENTS.md`.

1. `git fetch origin && git checkout -b hermes/<topic> origin/main`
2. Edit YAML. Append-only in `automations.yaml` (UI edits share it — never
   rewrite entries you didn't create). New dashboards: `<name>-dashboard.yaml`
   + `lovelace:` entry (copy the climate-dashboard pattern) + note for Josh
   to add the filename to `hass_control_config_files` in nas-infra.
3. `secrets.yaml` is not in this repo and never will be. Reference
   `!secret <name>`; list new names in the PR body.
4. PROVE IT on the dev HA instance (below) before pushing.
5. Commit (only repo files — never dev fixtures), push `hermes/<topic>`,
   stop. Final message = PR title + PR body with test evidence + Josh's
   manual steps. You cannot open PRs.

Hard rules: branches only, NEVER push main, NEVER force-push, never commit
credentials or key material, don't edit `.storage/`-style JSON.

## Dev HA instance — your proving ground

Throwaway HA Core (same version as live) next to you. Yours: deploy, break,
restart freely. No radios; entities are fakes you seed.

- Config dir `/workspace/ha-dev-config/` (its live `/config`), UI/API
  `$HA_DEV_URL` (Josh watches at http://192.168.1.61:8124).
- **Use `/workspace/bin/ha-dev`** — auth is handled for you:
  `check`, `reload <domain>`, `restart`, `deploy <file>...`,
  `seed <entity> <state> [attrs-json]`, `state`/`states [filter]`,
  `call <domain> <service> [json]`, `logbook [min]`, `errors`,
  `api <METHOD> <path> [json]`.
- Loop: `deploy` your YAML → `check` (must be valid) → `reload`
  (or `restart` if configuration.yaml changed) → `seed` trigger states with
  LIVE entity ids → verify `last_triggered` + `logbook` + `errors` → record
  evidence for the PR. Stub `!secret` values in a dev-only secrets.yaml.
- Live HA (`$HA_LIVE_URL` + `$HA_LIVE_TOKEN`) is READ-ONLY: GET only, for
  real entity ids/attributes. Never call services on it.

## /workspace/nas-infra — homelab IaC (Ansible/Nix/compose)

Pull-only remote (no push credential — intentional). Author on
`hermes/<topic>` locally, commit, and tell Josh the branch name; he fetches
it directly from this clone. Repo conventions: its `AGENTS.md` + `CLAUDE.md`
(written for trinity agents — path/skill references there don't apply to
you). Never decrypt or edit `group_vars/*/vault.yml`.
