# jhaycr-local.nixos_deploy

Thin wrapper: optionally writes out-of-band secret files, copies the repo's
NixOS config to the host, then runs `nixos-rebuild switch`.

## Variables
- `nixos_config_src`: source dir in this repo holding the NixOS config (e.g. `nix/smith`).
- `nixos_config_dest`: destination on the target host (default `/etc/nixos`).
- `nixos_use_flake`: build via `nixos-rebuild switch --flake <dest>#<host>` (default `true`) vs. legacy `nixos-rebuild switch`.
- `nixos_flake_host`: flake output name (default `{{ inventory_hostname }}`).
- `nixos_secret_files`: optional list (default `[]`) of files to write to the host before the rebuild - for Nix configs that expect a secret file to already exist on disk (e.g. rendered from `ansible-vault`) rather than managing secrets themselves. Nothing host-specific lives in this role; per-host content belongs in that host's `group_vars`. Each item:
  - `dest` (required): absolute path on the target host.
  - `content` (required): file content.
  - `owner` / `group` / `mode`: default `root` / `root` / `0600`.

## First deploy on a freshly-installed host

The manual bootstrap install (see e.g. `nix/smith/BRINGUP.md`) boots a
minimal `configuration.nix` that doesn't yet have Python, which
`ansible_python_interpreter: /run/current-system/sw/bin/python3` (the usual
NixOS interpreter path) points at. On a brand-new host that path won't exist
until the repo's own config (which installs `python3` via
`environment.systemPackages`) has been built at least once, so the very
first `nixos-rebuild switch` needs to be run manually over SSH rather than
through this role. Once that first rebuild lands, `python3` exists at that
path and subsequent `make <host>` runs work normally. Not worth
over-engineering (e.g. auto-falling-back interpreters) for a one-time
bootstrap step.
