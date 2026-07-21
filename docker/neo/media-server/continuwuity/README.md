# Matrix stack (continuwuity, element, baibot)

`continuwuity` (homeserver), `element` (web client), and `baibot` (Matrix ↔
LLM bridge to Hermes on smith) are a set — see also
`docker/neo/media-server/element/` and `docker/neo/media-server/baibot/`.

## Internal-only, on purpose — never add these to Traefik

This stack is deliberately **not** on Traefik and **not** listed in
`traefik_services` (`group_vars/neo/vars.yml`). Traefik is this repo's
externally-reachable path (fronted by `cloudflared`, reachable from the
public internet). Matrix's client-server API takes bearer tokens, not
browser cookies, so it can't sit behind Authentik's forward-auth middleware
the way most other services do — the only way to expose it externally
without also exposing raw, unauthenticated access to the homeserver API
would be `auth: none` in Traefik, which is worse than not exposing it at
all. Josh's call: this stays reachable only via WireGuard/LAN, full stop.

None of the three services carry a `networks:` key in their compose
templates, so they land on the media-server stack's `default` network
(`compose_default`) instead of `bridge_proxy_external` (the Traefik
network) — the same pattern used by `vaultwarden`, `healthchecks`, and
`jellyfin`. `npm-internal` is also on `default`, so it reaches them by
container name. `baibot` reaches `continuwuity` the same way
(`http://continuwuity:8008`, see `baibot/appdata/baibot/config.yaml.j2`).

**Do not** add `continuwuity` or `element` back to `traefik_services`, and
do not put `bridge_proxy_external` back in any of the three
`docker-compose.yml.j2` files. If a legitimate need for external Matrix
federation or external client access ever comes up, that's a deliberate
follow-up decision with its own auth story — not a config oversight to
"fix".

## Hostnames

Both hostnames use the `*.lab.{{ secret_domain }}` convention (resolves to
neo's LAN IP, 192.168.1.3 — see below):

- `matrix.lab.<domain>` — continuwuity (client-server API)
- `chat.lab.<domain>` — element (web client)

`server_name` is baked into every Matrix user ID (`@josh:matrix.lab.<domain>`)
and every federation event the moment an account is created, and can't be
changed afterwards without migrating to a brand-new homeserver identity.
It's set to the `.lab.` form in `continuwuity/.env.j2`,
`element/appdata/element/config.json.j2`, and
`baibot/appdata/baibot/config.yaml.j2`. If you ever need to change it again,
do it before the first account is registered — same as this time.

## Manual npm-internal setup (not templated)

`npm-internal`'s proxy hosts live in its own SQLite database, not in this
repo, so they can't be rendered from a template — add them by hand once,
in the admin UI at `http://192.168.1.3:81`:

1. **`matrix.lab.<domain>`** → forward to `continuwuity:8008`
   - Enable **Websockets Support** (Matrix sync uses long-polling/websockets)
   - SSL tab: use the existing `*.lab.<domain>` wildcard cert (same one
     `vaultwarden`/`healthchecks`/`jellyfin` use), force SSL
2. **`chat.lab.<domain>`** → forward to `element:80`
   - SSL tab: same `*.lab.<domain>` cert, force SSL

### DNS

`*.lab.<domain>` must already resolve to neo's LAN IP (192.168.1.3). This
is what makes the hostname reachable over WireGuard/LAN (where the resolver
sees 192.168.1.3 and can route to it) while remaining unreachable from the
public internet (an RFC1918 address isn't routable out there, so a public
DNS record pointing at it is safe by construction — nothing new to set up
here if `vaultwarden`/`healthchecks`/`jellyfin` already resolve correctly).

## Bootstrap sequence (first deploy)

1. Deploy the stack (`make neo-docker`) with
   `CONTINUWUITY_ALLOW_REGISTRATION=true` (the default in
   `continuwuity/.env.j2`) and the registration token set via
   `secret_continuwuity_registration_token`.
2. Add the two npm-internal proxy hosts above.
3. Register two accounts against `https://matrix.lab.<domain>` using the
   registration token:
   - `josh` — Josh's personal account (matches `matrix_admin_user` in
     `group_vars/neo/vars.yml`)
   - `hermes` — the bot account baibot logs in as
     (`user.mxid_localpart` in `baibot/appdata/baibot/config.yaml.j2`)
4. Flip `CONTINUWUITY_ALLOW_REGISTRATION` to `false` in
   `continuwuity/.env.j2` and redeploy (`make neo-docker`). Leaving
   registration open past this point means anyone who can reach
   `matrix.lab.<domain>` over WireGuard/LAN can create accounts.

## Required secrets

All in `group_vars/neo/vault.yml` (names only — see the vault file for
values, never grep it for secrets):

- `secret_continuwuity_registration_token`
- `secret_baibot_matrix_password`
- `secret_baibot_recovery_passphrase`
- `secret_baibot_session_encryption_key`
- `secret_baibot_config_encryption_key`
- `secret_hermes_api_key`
- `secret_baibot_groq_api_key` (from console.groq.com - used by the
  `whisper` static agent for speech-to-text)
- `secret_domain` (shared across the repo, not Matrix-specific)

## Voice messages

Send a voice message in Element X / FluffyChat to the Hermes bot and it
just works: baibot transcribes it via Groq's `whisper-large-v3-turbo` (the
`whisper` static agent in `baibot/appdata/baibot/config.yaml.j2`), then
automatically feeds the transcript to the `hermes` text-generation agent for
a reply - same as typing the message. If Josh ever wants transcription
without a reply, baibot's `Flow Type` setting (per-room, via bot commands)
can be switched to transcribe-only.

Note: this sends voice message audio to Groq, a third party. This is
consistent with the existing setup - Hermes's text generation already
routes through OpenRouter - so the LAN-only design here protects *access* to
the service, not the model calls it makes.
