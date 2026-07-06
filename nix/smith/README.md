# nix/smith

NixOS configuration for **smith** - a dedicated VM running the Hermes agent
(`nousresearch/hermes-agent`, josh profile). Replaces the archived Docker
container on neo: `docker/neo/ai/.archive/hermes-josh/{docker-compose.yml.j2,.env.j2}`.

**Status: bring-up complete.** The VM is installed and reachable at
`192.168.1.61`. `hardware-configuration.nix` and `ansible.pub` are committed.
`secrets.yaml` is still intentionally not committed - see section 2.

## 1. Manual bring-up (do this by hand in Proxmox)

1. On neo's Proxmox, pick a free VMID (check the current list in the UI;
   e.g. the `9000` NixOS/template is taken) and create a VM: 4 vCPU,
   6144 MB RAM, 32 GB disk on `local-lvm`, NIC on `vmbr0`.
2. Attach a NixOS minimal ISO (download from nixos.org, upload to Proxmox
   `local` storage) and boot it.
3. Run the standard NixOS manual install: partition/format, mount,
   `nixos-generate-config` to produce `hardware-configuration.nix`. Note the
   NIC's interface name (`ip link`, e.g. `ens18`) - needed in step 5.
4. Before the first `nixos-install`, hand-edit the installer's
   `/mnt/etc/nixos/configuration.nix` just enough to boot: enable `sshd`,
   create the `ansible` user (wheel, passwordless sudo,
   `~/.ssh/ansible.pub` as an authorized key - same key
   `playbooks/bootstrap-ssh.yml` uses), and set static networking for
   `192.168.1.61/24` via gateway `192.168.1.1` on the interface noted above.
5. `nixos-install`, reboot, confirm `ssh ansible@192.168.1.61` works.
6. Copy the generated `hardware-configuration.nix` from the VM into this
   directory, and uncomment its module line in `flake.nix`.
7. Copy your deploy pubkey into this directory as `ansible.pub` (e.g.
   `cp ~/.ssh/ansible.pub nix/smith/ansible.pub`), then uncomment
   `openssh.authorizedKeys.keyFiles = [ ./ansible.pub ];` in
   `configuration.nix`.
8. Fill in the real interface name in `configuration.nix`'s commented
   `networking.interfaces.<IFNAME>...` block and uncomment it - **required**
   before the first Ansible-driven rebuild, otherwise the host falls back to
   DHCP and loses the static IP set in step 4.
9. Add a DHCP reservation for the VM's MAC -> 192.168.1.61 in the UniFi
   Network app on the Express 7 (belt-and-suspenders alongside the static
   Nix config).
10. Uncomment the real IP in the root `inventory` file's `[smith]` group.

## 2. Secrets (sops-nix)

Four secrets are needed: an Anthropic API key, an OpenAI API key, an
OpenRouter API key (routes MiniMax/Qwen models through OpenRouter - no direct
MiniMax/DashScope secrets are held here), and an `API_SERVER_KEY`
(e.g. `openssl rand -hex 32`).

`sops`, `ssh-to-age`, and `age` are installed to `~/.local/bin` on trinity.
`.sops.yaml` in this directory has both age recipients filled in already
(smith's host key + the admin age key at `~/.config/sops/age/keys.txt`).

To create the encrypted secrets file:
```
sops nix/smith/secrets.yaml
```
This opens `$EDITOR` on an empty/decrypted buffer - populate it with:
```yaml
hermes_anthropic_api_key: <value>
hermes_openai_api_key: <value>
hermes_openrouter_api_key: <value>
hermes_api_server_key: <value>
```
Save - sops encrypts on write using the recipients from `.sops.yaml`. Then
commit the encrypted `secrets.yaml`. This is a separate mechanism from this
repo's `ansible-vault` files - `secrets.yaml` is safe to commit as-is (values
are individually encrypted) and is **not** covered by
`make vault-lock`/`vault-unlock` or the vault pre-commit hook.

`configuration.nix` decrypts these at NixOS activation via the host's own SSH
host key (auto-converted to age by sops-nix) plus the admin age key, and
renders two env files from them:

- `hermes-josh.env` - fed to the `hermes-josh` container via
  `environmentFiles` (functionally identical to the old `.env.j2`, plus the
  new `OPENROUTER_API_KEY`).
- `llm.env` - a second template (owner `ansible`, mode `0400`) holding the
  same three API keys (no `API_SERVER_KEY`) for interactive use. It's
  auto-sourced in interactive shells via `environment.interactiveShellInit`
  (guarded so shells that can't read the 0400 file just skip it), so
  `opencode` (installed declaratively via `environment.systemPackages`) picks
  up `OPENROUTER_API_KEY`/`ANTHROPIC_API_KEY`/`OPENAI_API_KEY` automatically
  in any interactive `ansible@smith` shell.

## 3. Deploy

Once the above is done:
```
make smith
```
runs `jhaycr-local.nixos_deploy`, which rsyncs this directory to
`/etc/nixos` on the VM and runs
`nixos-rebuild switch --flake /etc/nixos#smith`.

Verify: `podman ps` on the VM should show `hermes-josh` running; ports
`8642`/`9119` should respond locally on the VM; and
`http://192.168.1.3:3000` (Grafana/Loki) should show log lines with
`instance="smith"` once Alloy is shipping logs.
