# oracle (Home Assistant Green) — Ansible setup

`oracle` is a Home Assistant Green running Home Assistant OS at
`homeassistant.local` (`192.168.1.252`). HAOS is an immutable appliance, so it
is **not** managed with the normal role stack. Instead, the
[`bellackn.hass_control`](https://github.com/bellackn/ansible-role-hass-control)
Galaxy role version-controls the HA YAML config:

- **File transfer** rides the **Terminal & SSH addon** (already installed).
- **Restart** is triggered over the **HA REST API** with a long-lived token.
- Config lives in the repo under `files/home_assistant/` (and templates under
  `templates/home_assistant/`).

## One-time prerequisites (manual, on the HA side)

1. **SSH addon** (Terminal & SSH / Advanced SSH & Web Terminal) is installed.
   - Add the Ansible controller's public key to the addon's `authorized_keys`.
   - Note the SSH **port** and set `ansible_port` in `group_vars/oracle/vars.yml`
     if it isn't `22`.
2. **Long-lived access token**: HA profile page → *Long-Lived Access Tokens* →
   create one. Put it in the vault:
   ```bash
   # edit the (decrypted) vault file
   $EDITOR group_vars/oracle/vault.yml      # symlink -> ~/Secrets/.ansible-secrets/oracle.vault.yml
   # set: secret_oracle_ha_token: "<token>"
   make vault-lock
   ```

## Usage

```bash
make reqs            # installs bellackn.hass_control (first time only)
make oracle          # PULL: download current /config into files/home_assistant/ (safe, default)
# inspect the diff, then commit what's on the Green
make oracle-push     # PUSH: upload local files and restart HA
```

> **Always pull first** on a box with existing manual config so nothing is lost.
> After the first `make oracle`, update `hass_control_config_files` in
> `group_vars/oracle/vars.yml` to match what actually exists under `/config`.
