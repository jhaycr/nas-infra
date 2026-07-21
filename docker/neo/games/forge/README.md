# Forge (MTG) — how to start it

Forge is **manual-start**: it carries the compose `manual` profile and
`restart: "no"`, so `make neo-docker` renders its config but never starts it,
and a host/daemon reboot won't bring it back. You start it by hand when you
want to play, and stop it when you're done.

Runs as a LinuxServer Webtop (a browser-based XFCE desktop) with Forge
installed as a desktop app. Forge has **no server mode** — multiplayer is
peer-to-peer, so this always-on-when-you-want-it desktop is the "host seat"
and other players connect their own Forge clients to it.

## Start / stop

All commands run **on neo** (`ssh neo`), from the stack dir:

```bash
cd /opt/docker/compose/games

docker compose up -d forge      # start (auto-runs forge-init first, then forge)
docker compose stop forge       # stop
docker compose logs -f forge    # watch startup / install progress
```

Naming `forge` on `up` auto-activates its `manual` profile and pulls in its
`forge-init` helper — no `--profile` flag needed.

## Play

- Open the desktop UI in a browser: **http://192.168.1.3:3010**
- Launch the **Forge (MTG)** shortcut on the XFCE desktop.
- For a multiplayer game, host from inside this desktop; other players point
  their own Forge client at **neo:36743** (TCP). Everyone's Forge version must
  match the pinned one below.

## Version / cards / art

- Version is pinned in `group_vars/neo/vars.yml` as `forge_version`. New MTG
  cards ship *inside* each Forge release — to get new sets, bump that pin and
  reinstall (Renovate does **not** bump it; it points at a GitHub release, not
  an image tag).
- Card art auto-downloads from Scryfall into `/config` appdata on first use,
  so it persists across restarts and upgrades.

## If Forge isn't installed after starting

First-boot install can fail if the container predates the `bzip2` fix (the
`.tar.bz2` installer needs bzip2, which the base image lacks). Force a clean
recreate so it re-runs the installer with the current env:

```bash
cd /opt/docker/compose/games
docker compose up -d --force-recreate forge
docker compose logs forge | grep forge   # expect "Forge <version> installed"
```

See `../MTG-HANDOFF.md` for the full background, the bzip2 bug writeup, and
the `forge-init` chmod gotcha.
