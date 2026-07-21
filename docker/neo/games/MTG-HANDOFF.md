# MTG (Forge + XMage) — WIP handoff

Status as of 2026-07-20. Self-hosted Magic: The Gathering on the neo `games`
stack. **Both services are manual-start** (compose `manual` profile +
`restart: "no"`) — a `make neo-docker` deploy renders their config but never
starts them, and a daemon/host restart won't resurrect them.

## What's here

| Service | Image | Ports (host) | Purpose |
|---|---|---|---|
| `forge` | `lscr.io/linuxserver/webtop:ubuntu-xfce-*` | `3010`→web UI, `36743`→P2P | Forge MTG engine in a browser XFCE desktop |
| `forge-init` | `busybox:1.36.1` | — | one-shot: chmod the custom-cont-init.d script, then exits |
| `xmage` | `klastic/xmage-beta:1.4.60-dev_*` | `17171`, `17179` | XMage dedicated server (clients connect with their own XMage app) |

- **Forge** has no server mode — multiplayer is peer-to-peer; the webtop
  instance is the always-on host seat, others join `neo:36743` with their own
  Forge client (versions must match). Forge version pinned in
  `group_vars/neo/vars.yml` (`forge_version`); new cards ship inside each
  release — bump the pin + reinstall to update. Card art auto-downloads from
  Scryfall into `/config` appdata.
- **XMage** is true client/server with rules enforcement, but the server
  holds **no** card art — each player's client downloads its own.
- Files: `forge/docker-compose.yml.j2`,
  `forge/appdata/forge/custom-cont-init.d/10-install-forge.sh.j2`,
  `xmage/docker-compose.yml.j2`; plus the `include:` list, the override's
  no-restart carve-out, and `forge_version` in `group_vars/neo/vars.yml`.

## Known-good / already validated

- Templates render + YAML-parse clean; full games-stack merge simulation
  confirms minecraft/lazymc restart policies are untouched.
- Forge deployed once already and the container runs; the install script's
  staging-dir logic is idempotent and self-heals a failed prior attempt.

## The one real bug found (fixed here, NOT yet redeployed)

First deploy left Forge uninstalled: the webtop image ships `tar` + `curl`
but **no `bzip2`**, so `tar -xjf forge-installer-*.tar.bz2` failed (exit 2,
empty version dir). Fix in this commit: `INSTALL_PACKAGES: openjdk-17-jre|bzip2`
in `forge/docker-compose.yml.j2`. The dbus/polkit/X11 errors in the container
log are unrelated background noise from running a desktop — ignore them.

## TODO — what to do next (on trinity unless noted)

1. **Deploy the config:** `make neo-docker` (renders the corrected templates;
   won't start forge/xmage because they're profiled).
2. **Recreate the stale forge container on neo** so it picks up the bzip2 env
   (the running one predates the profile/bzip2 changes; a deploy won't touch
   it because it's profiled). On neo:
   ```bash
   cd /opt/docker/compose/games
   docker compose up -d --force-recreate forge
   ```
   The `INSTALL_PACKAGES` value changed, so plain `up -d forge` would also
   detect the diff and recreate — `--force-recreate` is belt-and-suspenders.
   Either way this reruns `forge-init` (fresh chmod) then forge's
   `custom-cont-init.d`, which now has `bzip2` and installs Forge for real.
   (If Compose ever refuses to recreate, fall back to
   `docker rm -f forge forge-init` then the `up` above.)
3. **Verify Forge installed:** on neo,
   `docker logs forge | grep forge-init` should show
   "Forge 2.0.13 installed" (not "tar ... exited 2"); and
   `ls /home/user0/docker/appdata/forge/forge/forge-2.0.13/forge.sh` exists.
   Then open `http://192.168.1.3:3010` and launch the "Forge (MTG)" desktop
   shortcut.
4. **Start XMage when wanted:** on neo,
   `cd /opt/docker/compose/games && docker compose up -d xmage`.
   Connect an XMage client to `192.168.1.3:17171`.
5. **Stop either game:** `docker compose stop forge` / `... stop xmage`.

## Gotchas to remember

- Naming a profiled service on `up` auto-activates its profile — no
  `--profile manual` flag needed; `-f` flags unneeded (compose auto-loads the
  override in the same dir).
- After editing `forge`/`xmage` templates later, a plain deploy won't
  recreate a running instance — re-run `docker compose up -d <svc>` by hand.
- LinuxServer `custom-cont-init.d` silently skips non-executable scripts; the
  compose role templates appdata at 0644, which is why `forge-init` exists.
- XMage image has an upstream env-var typo `XMAGE_DOCKER_SEONDARY_BIND_PORT`
  (baked into the image) — don't "fix" the spelling.
- Renovate bumps the Docker image tags but NOT `forge_version` (that pin
  points at a GitHub release, not an image) — bump it by hand.
