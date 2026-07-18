# AGENTS.md

This file describes the AI coding agents that operate in this repository and their guidelines.

## Repository Context

This is an Ansible IaC repository for homelab infrastructure. There is no build system, test suite, or linter — validation happens by running playbooks against real hosts. All changes should be reviewed carefully before deploying.

## Agent Roles

### Infrastructure Agent

Modifies Ansible playbooks, roles, variables, and inventory.

**Guidelines:**
- Always read `site.yml` and the relevant `group_vars/<host>/vars.yml` before making changes to understand what roles/tags apply to which hosts.
- Follow existing role naming: `jhaycr-local.*` for local roles, `jhaycr.*` for submodule roles.
- Secret variables must use the `secret_` prefix and go in `group_vars/<host>/vault.yml`.
- Never commit unencrypted vault files. Use `make vault-lock` before any commit.
- Roles installed from Galaxy (under `roles/` without `jhaycr` prefix) are gitignored — don't modify them directly.
- When editing role tasks, preserve existing tag structure (e.g., `compose`, `disks`, `pve`).

### Docker Service Agent

Adds or modifies Docker Compose service stacks.

**Guidelines:**
- Service compose files are Jinja2 templates (`.j2` extension) but should be mostly plain YAML with variable interpolation — avoid complex Jinja2 logic in service files.
- Every new service needs:
  1. `docker/<host>/<stack>/<service>/docker-compose.yml.j2`
  2. An entry in the parent stack's root `docker-compose.yml.j2` `include:` list
  3. Optional: `.env.j2`, `appdata/*.j2` for config templates
- Service names must be unique across all services in a stack (the override file applies to all).
- Use existing variables for paths: `docker_appdata_path`, `docker_compose_path`, `nas_storage_path`, `nas_cache_path`, `nas_download_path`.
- The override file (`docker-compose.override.yml.j2`) auto-applies to all services: restart policy, JSON logging, TZ/PUID/PGID env vars. Don't duplicate these in service files.
- Container names should match the service directory name.
- Always join the stack's `default` network unless there's a specific reason not to.
- When a service needs secrets, add `secret_*` variables to the appropriate vault file.
- To archive/disable a service, move it to `docker/<host>/<stack>/.archive/` and remove it from the `include:` list.

### Variable/Configuration Agent

Manages group_vars, host_vars, and variable organization.

**Guidelines:**
- Global defaults go in `group_vars/all.yml`.
- Host-specific config goes in `group_vars/<host>/vars.yml`.
- Encrypted secrets go in `group_vars/<host>/vault.yml` with `secret_` prefix.
- Symlink definitions go in `group_vars/<host>/symlinks.yml`.
- Don't put host-specific values in `all.yml` — use the host's own vars file.

## For Hermes (agent on smith, working in /workspace/nas-infra)

The sections above assume a trinity-side agent. If you are Hermes: you have
no ansible, no make targets, no vault key, and no access to any host — your
job ends at a well-tested local commit. Specifically:

- Branch `hermes/<topic>` from `origin/main`, commit locally, and report the
  branch name — the remote is pull-only for you (by design; don't work
  around it). Josh fetches your branch straight from this clone.
- Validate compose changes with `/workspace/bin/compose-check <file.j2>`
  (renders Jinja2 with stubs + YAML-parses). There is no other CI.
- Image references: verify the registry/repo actually exists (e.g.
  `docker.io` vs `ghcr.io` — check hub.docker.com or the project README)
  and pin a version tag, not `latest`; Renovate manages bumps.
- Port picks come from `docs/ports.md` (headless services: no ports at all).
- Deploys (`make neo-docker` etc.) are Josh's, from trinity, after review.

## Key Paths

| Path | Purpose |
|---|---|
| `site.yml` | Main playbook entrypoint |
| `inventory` | Static host inventory |
| `group_vars/` | Per-host and global variables |
| `roles/jhaycr-local.docker_compose/` | Core compose generation role |
| `docker/<host>/<stack>/` | Docker stack templates |
| `makefile` | Common make targets |
| `requirements.yml` | Galaxy dependencies |

## Validation

There are no automated tests. To validate changes:
- **Dry run:** `ansible-playbook site.yml --limit <host> --check --diff`
- **Debug compose:** `make neo-docker EXTRA_VARS="docker_compose_debug_print=true docker_compose_start_stack=false"`
- **Syntax check:** `ansible-playbook site.yml --syntax-check`
- Verify YAML syntax is valid — Ansible will fail on malformed YAML/Jinja2.

## Renovate Bot

Renovate auto-updates Docker image tags in `.j2` compose files matching `/^docker/.*\.ya?ml\.j2$/`. Some packages have version constraints in `renovate.json`. Files under `docker/morpheus/` and `docker/neo/.archive/` are excluded.
