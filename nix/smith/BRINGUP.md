# Smith VM — bring-up handoff

Task: bring a new NixOS VM named **smith** online on neo's Proxmox and get the
Hermes agent (`nousresearch/hermes-agent`, josh profile) running on it, then
deploy it from this repo. All the repo-side scaffolding already exists; this doc
covers finishing bring-up and deploying.

## Context (read first)

- **Repo:** `~/Code/ansible/nas-infra` (Ansible IaC homelab). Work here always
  goes through the repo's normal patterns — mirror the existing `osiris` NixOS
  host, which this was modeled on.
- **What smith is:** a dedicated NixOS **VM** (not LXC) running a single
  Hermes agent container. It replaces an archived Docker service at
  `docker/neo/ai/.archive/hermes-josh/`. Identity: hostname `smith`, static IP
  **192.168.1.61/24**, gateway 192.168.1.1. Sizing: 4 vCPU / 6 GB RAM / 32 GB.
  (Matrix naming: neo/morpheus/trinity/oracle/smith — the VM/host identity is
  `smith`; the container/service it runs keeps the name `hermes-josh`.)
- **How deploy works:** `make smith` runs the `jhaycr-local.nixos_deploy` role,
  which rsyncs `nix/smith/` → `/etc/nixos` on the VM and runs
  `nixos-rebuild switch --flake /etc/nixos#smith`. The role does NOT create the
  guest — the VM must be created and NixOS installed by hand first (this doc).
- **Network:** the UniFi controller is a standalone **Express 7** (UniFi Network
  app), not a Proxmox VM. DHCP reservations are set there.
- **Secrets:** this repo's standard `ansible-vault` workflow, NOT sops-nix
  (an earlier iteration used sops-nix; superseded — see git history if
  curious). Secrets live in `group_vars/smith/vault.yml` as `secret_*` vars
  (naming matches the archived Docker `.env.j2`), edited via
  `make vault-unlock` / `make vault-lock` like every other host. They're
  rendered into plain env files **on the host** by
  `jhaycr-local.nixos_deploy`'s `nixos_secret_files` var
  (`group_vars/smith/vars.yml`) before every rebuild. Nothing secret-related
  lives in `nix/smith/` at all. Secret var names keep the `hermes_josh_*`
  segment (they belong to the Hermes agent/profile, not the host) — only the
  host/VM/repo-wiring identity is `smith`.

### Already committed / scaffolded (do not recreate)

- `nix/smith/flake.nix` — plain nixpkgs flake (no sops-nix input). The
  `hardware-configuration.nix` module line is wired in.
- `nix/smith/configuration.nix` — podman `oci-containers` def for `hermes-josh`
  (matches the archived compose field-for-field), `services.alloy`. Expects
  `/etc/hermes/hermes-josh.env` and `/etc/hermes/llm.env` to already exist on
  disk (written by Ansible, not by this config).
- `nix/smith/alloy-config.alloy` — journald → neo Loki
  (`http://192.168.1.3:3100/loki/api/v1/push`), label `instance="smith"`.
- `nix/smith/README.md` — reference for the same workflow.
- `group_vars/smith/vars.yml` (incl. `nixos_secret_files`), `group_vars/smith/vault.yml`
  (plaintext scaffold — fill in and `make vault-lock` before committing),
  `[smith]` group in `inventory`, `- hosts: smith` play in `site.yml`,
  `smith:` target in `makefile`.

### Produced during bring-up (not scaffolded ahead of time)

- `nix/smith/hardware-configuration.nix` — generated on the VM.
- `nix/smith/ansible.pub` — the deploy pubkey.

---

## Step 1 — Create the VM (Proxmox web UI on neo)

Interactive/UI, cannot be scripted here. Guide the user through it if they
haven't done it:

1. Download a **NixOS minimal ISO** from nixos.org; upload to Proxmox `local`
   storage.
2. Create a VM: **4 vCPU, 6144 MB RAM, 32 GB disk on `local-lvm`, NIC on
   `vmbr0`**. Any free VMID (check the current list in the UI).
3. In the UniFi Express 7 Network app, reserve **192.168.1.61** for this VM's
   MAC, or otherwise keep .60 outside the DHCP pool.
4. Boot the VM from the ISO.

## Step 2 — Install NixOS (in the VM console)

Single-disk layout — GPT with a 512M ESP partition regardless of whether the
VM is booting BIOS or UEFI (check `/sys/firmware/efi`: if absent, the VM is
legacy BIOS and needs GRUB, not systemd-boot, even though an ESP partition was
created). User runs these in the VM:

```bash
# Partition (assuming disk is /dev/sda) — GPT + 512M ESP + rest as root:
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart primary 512MiB 100%
sudo mkfs.fat -F32 -n boot /dev/sda1
sudo mkfs.ext4 -L nixos /dev/sda2

# Mount:
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/boot /mnt/boot

# Generate config:
sudo nixos-generate-config --root /mnt
ip link       # NOTE the NIC name (e.g. ens18) — needed later
ls /sys/firmware/efi 2>/dev/null || echo "legacy BIOS - use GRUB"
```

Hand-edit `/mnt/etc/nixos/configuration.nix` to make the box bootable and
reachable (this is throwaway bootstrap config — the repo's config takes over
after first deploy). Ensure:

- `boot.loader.grub.enable = true; boot.loader.grub.device = "/dev/sda";` if
  legacy BIOS (no `/sys/firmware/efi`) — `boot.loader.systemd-boot.enable = true;`
  only applies if the VM is actually booting UEFI.
- `services.openssh.enable = true;` and `services.openssh.settings.PermitRootLogin = "no";`
- an `ansible` user:
  ```nix
  users.users.ansible = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "<paste the ansible deploy pubkey>" ];
  };
  security.sudo.wheelNeedsPassword = false;
  ```
- static networking on the NIC noted above:
  ```nix
  networking.hostName = "smith";
  networking.networkmanager.enable = false;
  networking.useDHCP = false;
  networking.interfaces.<IFNAME>.ipv4.addresses = [
    { address = "192.168.1.61"; prefixLength = 24; }
  ];
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "192.168.1.1" ];
  ```

Then:
```bash
sudo nixos-install --no-root-passwd
reboot
```

Verify from trinity: `ssh ansible@192.168.1.61 'true'` succeeds.

## Step 3 — Wire the VM back into the repo (on trinity)

```bash
cd ~/Code/ansible/nas-infra

# hardware config from the VM into the repo:
scp ansible@192.168.1.61:/etc/nixos/hardware-configuration.nix nix/smith/

# deploy pubkey into the repo:
cp ~/.ssh/ansible.pub nix/smith/ansible.pub
```

Then edit these files to uncomment the placeholders:

- `nix/smith/flake.nix` — uncomment the `./hardware-configuration.nix` module line.
- `nix/smith/configuration.nix` —
  - uncomment `openssh.authorizedKeys.keyFiles = [ ./ansible.pub ];`
  - uncomment the `networking.interfaces.<IFNAME>...` block and replace
    `<IFNAME>` with the real NIC name from step 2.
  - confirm `system.stateVersion` matches the installed NixOS release.
- `inventory` — uncomment the `192.168.1.61` line under `[smith]`.

## Step 4 — Secrets (ansible-vault, on trinity)

```bash
cd ~/Code/ansible/nas-infra
make vault-unlock          # decrypts all group_vars/*/vault.yml, incl. smith's
```

Edit `group_vars/smith/vault.yml`, filling in the four `secret_*` values
(key names keep the `hermes_josh_` segment — they belong to the agent/profile,
not the host):
```yaml
secret_hermes_josh_anthropic_api_key: "<value>"
secret_hermes_josh_openai_api_key: "<value>"
secret_hermes_josh_openrouter_api_key: "<value>"   # routes MiniMax/Qwen via OpenRouter
secret_hermes_josh_api_server_key: "<value>"       # e.g. openssl rand -hex 32
```

```bash
make vault-lock             # re-encrypts before committing
```

These four secrets get rendered into two plain env files **on the host** by
`jhaycr-local.nixos_deploy`'s `nixos_secret_files` var (see
`group_vars/smith/vars.yml`), written before every rebuild:
`/etc/hermes/hermes-josh.env` (feeds the `hermes-josh` container) and
`/etc/hermes/llm.env` (interactive OpenCode use, auto-sourced via
`environment.interactiveShellInit`). `nix/smith/configuration.nix` has no
secret-handling of its own — it just expects both files to exist.

## Step 5 — Deploy

```bash
cd ~/Code/ansible/nas-infra
make smith
```

If `services.alloy` fails to evaluate on the pinned nixpkgs, fall back to a
plain `systemd.services.alloy` unit running `pkgs.grafana-alloy` with
`--config.file=./alloy-config.alloy` (noted in `configuration.nix`), then
re-run `make smith`.

## Step 6 — Verify

```bash
ssh ansible@192.168.1.61 'podman ps'                          # hermes-josh Up
ssh ansible@192.168.1.61 'systemctl status podman-hermes-josh'
ssh ansible@192.168.1.61 'systemctl status alloy'
ssh ansible@192.168.1.61 'curl -sf http://127.0.0.1:8642/ >/dev/null && echo ok'
```

Then in Grafana/Loki (`http://192.168.1.3:3000`) query `{instance="smith"}` to
confirm log shipping. Check the container's startup logs for a clean API-key
load (no auth errors) to confirm `/etc/hermes/hermes-josh.env` (written by
Ansible before the rebuild) reached the container correctly.

## Step 7 — Commit

Once verified, commit the newly added `hardware-configuration.nix`,
`ansible.pub`, and the uncommented edits, plus `group_vars/smith/vault.yml`
**encrypted** (run `make vault-lock` first — this one, unlike the rest of
`nix/smith/`, goes through the normal vault flow) and
`group_vars/smith/vars.yml`.

## Guardrails

- `group_vars/smith/vault.yml` follows the same rules as every other host's
  vault file: edit only via `make vault-unlock` / `make vault-lock`, never
  commit it decrypted (the pre-commit hook blocks this anyway).
- Do not run `make smith` until steps 1–4 are complete (the VM and its
  hardware-config/secrets must exist first).
- Mirror `nix/osiris/` conventions for any Nix-side style questions.

## Dev HA instance (ha-dev) — provisioning & reset

The `ha-dev` oci-container is Hermes's proving ground: a throwaway HA Core
pinned to oracle's Core version (bump the image tag in `configuration.nix`
when oracle upgrades). Config lives in `/var/lib/ha-dev` (= container
`/config`), which the hermes-josh container sees read-write at
`/workspace/ha-dev-config`. Login: owner user `hermes`, password in vault as
`secret_hermes_josh_ha_dev_password` (rendered to `/etc/hermes/ha-dev.env`).
UI on the LAN: http://192.168.1.61:8124.

Provision (first boot, or after a reset) — all over plain HTTP from any LAN
machine; `PW` = the vault password value, `BASE=http://192.168.1.61:8124`,
`CID="$BASE/"`:

1. `POST $BASE/api/onboarding/users`
   `{"client_id":CID,"name":"Hermes","username":"hermes","password":PW,"language":"en"}`
   → returns `auth_code`. Exchange at `POST $BASE/auth/token`
   (`grant_type=authorization_code`, `code`, `client_id=CID`) → access token.
2. With the token: `POST /api/onboarding/core_config`,
   `POST /api/onboarding/analytics`, and `POST /api/onboarding/integration`
   (`{"client_id":CID,"redirect_uri":CID}`) — all three must return 200.
3. Set timezone to match oracle (websocket `config/core/update`,
   `{"time_zone":"America/Los_Angeles"}`) — REST has no endpoint for this;
   run it via `podman exec ha-dev python3` + aiohttp, or from the UI
   (Settings → System → General).

Reset to a blank slate:
`systemctl stop podman-ha-dev && rm -rf /var/lib/ha-dev/* /var/lib/ha-dev/.storage /var/lib/ha-dev/.cloud && systemctl start podman-ha-dev`,
then re-provision as above.

Gotcha: don't `systemctl stop podman-ha-dev` in the first ~2 minutes after
onboarding — HA debounces `.storage` writes and an early stop can truncate
`core.config` (seen during bring-up: empty `core.config.tmp`, instance falls
back to UTC defaults). Fix by re-running the websocket `config/core/update`.
