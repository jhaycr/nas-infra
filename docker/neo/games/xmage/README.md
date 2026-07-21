# XMage — how to start it

XMage is **manual-start**: it carries the compose `manual` profile and
`restart: "no"`, so `make neo-docker` renders its config but never starts it,
and a host/daemon reboot won't bring it back. Start it by hand when you want
to play, stop it when you're done.

Unlike Forge, XMage is a true **client/server** MTG engine with full rules
enforcement. This container is the *server* only — each player connects with
their own XMage desktop client. The server holds **no** card art; every client
downloads its own.

## Start / stop

All commands run **on neo** (`ssh neo`), from the stack dir:

```bash
cd /opt/docker/compose/games

docker compose up -d xmage      # start
docker compose stop xmage       # stop
docker compose logs -f xmage    # watch startup
```

Naming `xmage` on `up` auto-activates its `manual` profile — no `--profile`
flag needed.

## Connect

In your XMage client, add/connect to a server:

- **Host:** `192.168.1.3`
- **Port:** `17171`

Authentication is disabled (`XMAGE_DOCKER_AUTHENTICATION_ACTIVATED: "false"`),
so no account is needed. Persistent data (DB + saved games) lives under
`{{ docker_appdata_path }}/xmage/` on neo.

## Version

Pinned by image tag `klastic/xmage-beta:<xmage_version>-dev_<build_date>` in
`docker-compose.yml.j2` (Renovate-managed). Check
<https://hub.docker.com/r/klastic/xmage-beta/tags> for newer dev builds.

> Note: the image bakes in an upstream env-var typo
> `XMAGE_DOCKER_SEONDARY_BIND_PORT` — do **not** "fix" the spelling.

See `../MTG-HANDOFF.md` for the full MTG (Forge + XMage) background.
