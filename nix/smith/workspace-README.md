# /workspace command reference (smith)

How to pull, push, talk to GitHub, and get changes deployed. The rules live
in `WORKFLOW.md` — read that first; this file is just the commands.

## Repos in this workspace

| Path | Remote | Access |
|---|---|---|
| `/workspace/nas-infra` | `https://github.com/jhaycr/nas-infra` (public) | **pull-only** |
| `/workspace/home-assistant-config` | `git@github.com:jhaycr/home-assistant-config` (private) | pull + push `hermes/*` branches (deploy key) |

Deterministic tools live in `/workspace/bin/` (root-owned; run, don't edit):
`ha-dev` wraps the entire dev-HA test loop, `compose-check` validates
compose `.j2` files, `neo-diag` gives read-only container logs/status on
neo — see `WORKFLOW.md`.

Git identity (`Hermes (smith)`) is already configured in both clones.

## Pull — get latest

```sh
# nas-infra (Ansible IaC for the whole homelab)
git -C /workspace/nas-infra pull

# home-assistant-config — always start work from fresh main
git -C /workspace/home-assistant-config fetch origin
git -C /workspace/home-assistant-config checkout -b hermes/<topic> origin/main
```

## Push — publish your work

**home-assistant-config only.** The repo-local `core.sshCommand` already
points at the deploy key (`/etc/hermes/ha-config-deploy.key`); no ssh-agent
or extra setup needed:

```sh
git -C /workspace/home-assistant-config push -u origin hermes/<topic>
```

Branches only — never push to `main`, never force-push (WORKFLOW.md).

**nas-infra is pull-only** (https remote, no deploy key installed). If a task
produces nas-infra changes, commit them locally on a `hermes/<topic>` branch
and tell Josh the branch exists — he'll fetch it or set up push access.
Do not try to work around this.

## GitHub

There is no `gh` CLI and no GitHub API token in this environment — the only
GitHub credential is the HA deploy key. Consequences:

- You can push branches to `home-assistant-config`, but you **cannot open
  pull requests**. After pushing, put the ready-to-paste PR title and body
  (including your dev-instance test evidence) in your final message; Josh
  opens the PR at `github.com/jhaycr/home-assistant-config`.
- You cannot read issues, PR comments, or CI status. Ask Josh to paste
  anything you need from GitHub.

## Deploying to downstream machines

You have **no access to any live system** (oracle, neo, trinity, morpheus) —
deploys always run from trinity, by Josh, after review. So "deploy" for you
means: finish the branch, then tell Josh exactly what to run. Reference:

| Change merged | Josh runs (from trinity, nas-infra checkout) |
|---|---|
| HA config (`home-assistant-config`) | `bash .claude/skills/ha-control/scripts/write/push-config.sh --confirm` (auto-backup, then push to oracle) |
| nas-infra: docker stack on neo | `make neo-docker` |
| nas-infra: neo system/roles | `make neo` (or `make neo-disks` / `make neo-pve`) |
| nas-infra: this VM (smith) | `make smith` |
| nas-infra: trinity | `make trinity` / `make trinity-docker` |

The one thing you deploy to directly is your own dev HA instance
(`/workspace/ha-dev-config`, API at `$HA_DEV_URL`) — test loop in
`WORKFLOW.md`.
