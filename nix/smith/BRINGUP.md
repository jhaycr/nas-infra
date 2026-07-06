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
- **Secrets:** sops-nix, NOT ansible-vault. Do not touch `group_vars/*/vault.yml`
  for this. The secrets live in `nix/smith/secrets.yaml` (sops-encrypted,
  safe to commit, not covered by the repo's vault pre-commit hook). Secret key
  names keep the `hermes_*` prefix (they belong to the Hermes agent, not the
  host) — only the host/VM/repo-wiring identity is `smith`.

### Already committed / scaffolded (do not recreate)

- `nix/smith/flake.nix` — flake with `sops-nix` input. The
  `hardware-configuration.nix` module line is **commented out** pending bring-up.
- `nix/smith/configuration.nix` — podman `oci-containers` def for `hermes-josh`
  (matches the archived compose field-for-field), sops secret+template wiring,
  `services.alloy`. Has **commented-out** placeholders for: the static-IP block
  (`<IFNAME>`), and the `authorizedKeys.keyFiles = [ ./ansible.pub ]` line.
- `nix/smith/alloy-config.alloy` — journald → neo Loki
  (`http://192.168.1.3:3100/loki/api/v1/push`), label `instance="smith"`.
- `nix/smith/.sops.yaml` — recipient scaffold with two `age1TODO_...`
  placeholders (host key + admin key) to be replaced.
- `nix/smith/README.md` — reference for the same workflow.
- `group_vars/smith/vars.yml`, `[smith]` group in `inventory` (IP commented
  out), `- hosts: smith` play in `site.yml`, `smith:` target in `makefile`.

### Intentionally NOT committed (produced during bring-up)

- `nix/smith/hardware-configuration.nix` — generated on the VM.
- `nix/smith/ansible.pub` — the deploy pubkey.
- `nix/smith/secrets.yaml` — can't be encrypted until the VM's host key exists.

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

## Step 4 — Secrets (sops-nix, on trinity)

```bash
# one-time local tools (NOT in repo tooling — install via nix/go/pkg mgr):
#   sops, ssh-to-age

# host age key (VM must be up from step 2):
ssh-keyscan -t ed25519 192.168.1.61 | ssh-to-age
# admin age key (your personal key, so you can edit secrets from trinity):
cat ~/.ssh/id_ed25519.pub | ssh-to-age
```

- Replace both `age1TODO_...` placeholders in `nix/smith/.sops.yaml` with the
  two age keys above.
- Create + encrypt the secrets:
  ```bash
  sops nix/smith/secrets.yaml
  ```
  Populate (key names keep the `hermes_` prefix — they belong to the agent,
  not the host):
  ```yaml
  hermes_anthropic_api_key: <value>
  hermes_openai_api_key: <value>
  hermes_openrouter_api_key: <value>   # routes MiniMax/Qwen via OpenRouter
  hermes_api_server_key: <value>   # e.g. openssl rand -hex 32
  ```
  Save (sops encrypts on write). These four secrets feed both
  `hermes-josh.env` (the container) and `llm.env` (interactive OpenCode use,
  auto-sourced via `environment.interactiveShellInit`).

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
load (no auth errors) to confirm the sops-rendered env file reached the
container.

## Step 7 — Commit

Once verified, commit the newly added `hardware-configuration.nix`,
`ansible.pub`, `secrets.yaml`, and the uncommented edits. Do **not** run
`make vault-lock` for these — they are sops-managed, not ansible-vault.

## Guardrails

- Never read/inspect `group_vars/*/vault.yml`. Not needed here — smith uses
  sops-nix, a separate mechanism.
- Do not run `make smith` until steps 1–4 are complete (the VM and its
  hardware-config/secrets must exist first).
- Mirror `nix/osiris/` conventions for any Nix-side style questions.
