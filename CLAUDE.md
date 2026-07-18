# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible IaC for a homelab managing hosts `neo` (primary NAS/media server/Proxmox), `morpheus` (Proxmox), `trinity` (local workstation), `oracle`, `deck`, and `unifi`. Entrypoint is `site.yml`, which applies roles per host.

## Common Commands

```bash
make reqs                        # Install Galaxy roles/collections from requirements.yml
make neo                         # Run site.yml for neo, skip compose
make neo-docker                  # Run site.yml for neo, compose tag only
make neo-disks                   # Run site.yml for neo, disks tag only
make neo-pve                     # Run site.yml for neo, pve tag only
make morpheus                    # Run site.yml for morpheus, skip compose
make trinity                     # Run site.yml for trinity, skip compose (prompts sudo)
make trinity-docker              # Run site.yml for trinity, compose tag only
make compose                     # Run compose tag for all hosts
make vault-unlock                # Decrypt all group_vars/*/vault.yml
make vault-lock                  # Re-encrypt all group_vars/*/vault.yml
make bootstrap-ssh LIMIT=<host>  # Bootstrap SSH on a new host

# Pass extra vars to any target:
make neo-docker EXTRA_VARS="docker_compose_debug_print=true"
make neo-docker EXTRA_VARS="docker_compose_start_stack=false"
```

## Architecture

### Variable Hierarchy

- `group_vars/all.yml` - global defaults (users, IPs)
- `group_vars/<host>/vars.yml` - host-specific config (paths, packages, storage)
- `group_vars/<host>/vault.yml` - encrypted secrets (prefix: `secret_*`)
- Vault key lives **outside** the repo at `../.ansible-vault.key`

### Docker Compose Stack Layout

Stacks live under `docker/<host>/<stack>/`. Each stack contains:
- Root `docker-compose.yml.j2` with `include:` list referencing service subdirs
- `docker-compose.override.yml.j2` - Jinja2-templated, auto-applies common defaults (restart, logging, TZ/PUID/PGID) to all discovered services
- `<service>/docker-compose.yml.j2` - individual service definitions
- `<service>/.env.j2` (optional) - per-service env
- `<service>/appdata/*.j2` (optional) - config files rendered to `docker_appdata_path`

### Compose Generation Flow (`jhaycr-local.docker_compose` role)

1. `1_templates.yml` - finds and renders all `.j2` templates to target paths
2. `2_overrides.yml` - parses root `include` list, gathers service names, renders override
3. `3_docker.yml` - runs `docker compose up`, prunes dangling images

Key toggle vars (set via `EXTRA_VARS` or env):
- `docker_compose_debug_print` / `docker_compose_debug_halt` - debugging
- `docker_compose_copy_templates` / `docker_compose_start_stack` - control execution
- `docker_compose_restart` - restart policy (never/always/auto)

### Adding a New Docker Service

1. Create `docker/<host>/<stack>/<service>/docker-compose.yml.j2`
2. Add the service to the root stack's `include:` list
3. Optionally add `.env.j2` and `appdata/*.j2` templates
4. If secrets needed, add `secret_*` vars to the host's `vault.yml`
5. Deploy: `make neo-docker`

### Role Naming

- `jhaycr-local.*` - custom roles in this repo
- `jhaycr.*` - custom roles as git submodules
- Others (geerlingguy, IronicBadger, etc.) - Galaxy-installed, reinstall with `make reqs`

### Key Jinja2 Variables in Compose Templates

- `{{ docker_appdata_path }}` - appdata base (neo: `/home/user0/docker/appdata`)
- `{{ docker_compose_path }}` - compose output (neo: `/opt/docker/compose`)
- `{{ nas_storage_path }}` - merged storage mount (`/mnt/storage`)
- `{{ nas_cache_path }}` - fast cache disk (`/mnt/cache1`)
- `{{ nas_download_path }}` - downloads (`{{ nas_cache_path }}/downloads`)
- `{{ main_username }}` - primary OS user (`user0`)

### Storage (neo)

LUKS-encrypted disks -> SnapRAID parity -> MergerFS union at `/mnt/storage`. Safe-shutdown systemd service ensures clean teardown.

### Vault Safety

Pre-commit hook (`git_hooks/pre-commit`) blocks commits if any vault file is unencrypted. Install hooks after cloning: `bin/create_githook_symlinks.sh`.

## Home Assistant (oracle / HA Green)

For ANY task involving Home Assistant, the HA Green, or the `oracle` host —
diagnosing, changing settings, editing automations/scenes/dashboards — first
read `files/home_assistant/CLAUDE.md` (private submodule). It covers access
methods (SSH/Ansible raw/REST API), the pull→edit→push config workflow
(`make oracle-pull` / `make oracle-push`), safety rules, and links to a full
system inventory in `files/home_assistant/docs/`.

**Writes to HA are backup-gated.** Use the `ha-control` skill
(`.claude/skills/ha-control/`): `inspect/*` scripts are read-only,
`write/*` scripts take a Supervisor backup before acting (dry-run by default,
`--confirm` needs user approval). Direct ssh/scp/ansible write commands to
192.168.1.152 are blocked by a PreToolUse hook; `make oracle-push` is allowed
because a site.yml pre_task backs up first.

## Supplemental Docs

`.sop/summary/` contains auto-generated architecture docs (may be stale). `.github/copilot-instructions.md` has additional context.

@AGENTS.md