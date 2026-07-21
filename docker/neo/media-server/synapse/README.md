# Matrix stack (Synapse + Element + baibot → Hermes)

Self-hosted Matrix so Josh can chat with the **Hermes** agent (on smith) from a
phone, **LAN/WireGuard only**. Three services in the media-server stack:

- `synapse` — homeserver (this dir)
- `element` — web client (`../element/`), at `chat.lab.<domain>`
- `baibot` — Matrix↔LLM bridge (`../baibot/`); logs in as `@hermes`, relays to
  Hermes's OpenAI-compatible API on smith, and does voice via Groq Whisper.

## Why Synapse (and NOT continuwuity)

This stack was first built on **continuwuity** (lightweight conduwuit fork) and
it did **not work** — two separate matrix-sdk sync bugs broke the bot:
1. [#779](https://forgejo.ellis.link/continuwuation/continuwuity/issues/779) —
   a room's state isn't sent to a client on join (bot can't get power levels).
2. A timeline/thread-fetch hang — baibot got stuck on `eyeball: No wakers`
   waiting for conversation history that continuwuity never delivered, so it
   never even called Hermes. Persisted even on continuwuity's `main` build.

**Lesson: don't run bots / matrix-sdk clients against continuwuity/conduwuit.**
Synapse (the reference server) does all of this correctly, including encrypted
rooms. The old continuwuity attempt is archived at `../.archive/continuwuity/`
(its README has the full #779 writeup + the `resync-baibot.sh` workaround).

## Lean config (Josh has 32GB for the WHOLE homelab)

Tuned for a single user, so Synapse measures **~110 MB RSS** (not the 600MB-1GB
of a default install). See `appdata/synapse/homeserver.yaml.j2`:
- **SQLite, no postgres** (`database.name: sqlite3`) — fine for one user + a bot.
- Federation OFF (`federation_domain_whitelist: []`), presence OFF, URL previews
  OFF, `caches.global_factor: 0.5`.
- Runs as `user: "1000:1000"` so it owns the appdata bind-mount.

## Internal-only — never add to Traefik

Not in `traefik_services`, no `networks:` key (lands on the media-server
`default` net so npm-internal + baibot reach it by name). Reachable only via
npm-internal + `*.lab.<domain>` DNS → 192.168.1.3 (a public record on a private
IP: routable on WireGuard/LAN, dead from the internet). Matrix's client-server
API is bearer-token, not cookie, so it can't sit behind Authentik forward-auth.

## Setup / rebuild runbook

1. Secrets in `group_vars/neo/vault.yml`:
   `secret_synapse_{registration_shared_secret,macaroon_secret_key,form_secret}`.
2. `make neo-docker` renders `homeserver.yaml` + `log.config` to
   `{{ docker_appdata_path }}/synapse/`.
3. **Signing key** (once, not templated/not a vault secret): a file
   `/data/signing.key` of the form `ed25519 <version> <unpadded-base64 32-byte
   seed>`, owned by uid 1000. Synapse won't start without it.
4. Register accounts (no bootstrap-token quirk — plain shared secret):
   `docker exec -it synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
   — make `josh` (admin) and `hermes` (baibot's account, `--no-admin`).
5. baibot: if it was previously pointed at a different homeserver, delete its
   persisted session (`{{ docker_appdata_path }}/baibot/{db,session.json}`) so it
   re-authenticates — otherwise the old access token 401s.

## Manual npm-internal proxy hosts (not templated)

At `http://192.168.1.3:81` — forward with **Websockets ON**, SSL = the
`*.lab.<domain>` Cloudflare DNS-01 wildcard cert:
- `matrix.lab.<domain>` → `synapse:8008`
- `chat.lab.<domain>` → `element:80`

## Phone

Element X or FluffyChat → log in `@josh:matrix.lab.<domain>` → invite
`@hermes:matrix.lab.<domain>` **by full MXID** (bots don't always show in the
user-directory search) → chat. Voice messages transcribe via Groq then go to
Hermes. See `../baibot/appdata/baibot/config.yaml.j2`.
