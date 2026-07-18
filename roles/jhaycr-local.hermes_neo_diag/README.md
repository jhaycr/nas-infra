# jhaycr-local.hermes_neo_diag

Read-only docker/network diagnostics on **neo** for the Hermes agent on
**smith**. Gives the agent `docker logs / ps / health` and socket listeners —
and provably nothing else.

## How it's enforced (server-side, on neo)

```
agent runs /workspace/bin/neo-diag logs minecraft-proxy 400
  └─ ssh -i /etc/hermes/neo-diag.key hermes-diag@192.168.1.3 logs minecraft-proxy 400
       └─ authorized_keys: command="hermes-neo-diag-shim",restrict   ← key can ONLY run the shim
            └─ shim (unprivileged): word-splits SSH_ORIGINAL_COMMAND, no eval
                 └─ sudo hermes-neo-diag-root <argv>                 ← the ONLY sudoers entry
                      └─ root dispatcher: validates names/counts, fixed
                         read-only menu (docker logs/ps/inspect, ss -ltnu)
```

The client script on smith is convenience only; every guarantee lives in this
role's three files (shim, dispatcher, sudoers) plus the `restrict` key option
(no pty, no forwarding). The dispatcher is root-owned — the hermes-diag user
can't edit what it's allowed to run.

## Rebuilding from scratch (e.g. after a smith rebuild)

1. **Generate the keypair on smith** (private key lives only there, never in
   a repo or vault):
   ```bash
   ssh ansible@192.168.1.61 sudo sh -c \
     'ssh-keygen -t ed25519 -N "" -C hermes-diag@smith -f /etc/hermes/neo-diag.key \
      && chown 10000:10000 /etc/hermes/neo-diag.key* && chmod 0400 /etc/hermes/neo-diag.key'
   ```
   (uid 10000 = the in-container agent user; rootful podman, no userns remap.)
2. **Update the public key** in `defaults/main.yml`
   (`hermes_neo_diag_pubkey`) with the new `.pub` output; commit.
3. **Deploy the neo side**:
   ```bash
   ansible-playbook site.yml --limit neo --tags hermes-diag
   ```
4. **Deploy the smith side** (mounts `nix/smith/neo-diag.sh` read-only at
   `/workspace/bin/neo-diag` in the hermes container): `make smith`
5. **Verify** — positive and negative:
   ```bash
   bash .claude/skills/hermes-agent/scripts/canary.sh        # includes neo-diag checks
   # negative test - arbitrary commands must be rejected by the dispatcher:
   ssh ansible@192.168.1.61 sudo podman exec hermes-josh \
     su hermes -s /bin/sh -c '"/workspace/bin/neo-diag whoami"'   # → usage error, exit 2
   ```

Rotation = repeat steps 1–3. Revoke instantly by deleting the
`hermes-diag` user on neo or its `~/.ssh/authorized_keys` entry.
