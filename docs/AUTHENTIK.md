# Authentik Blueprints

## Overview

Authentik providers and applications for OIDC-integrated services are managed via [Blueprints](https://docs.goauthentik.io/docs/customize/blueprints/). Blueprints are declarative YAML files that Authentik applies on startup, keeping SSO configuration in version control rather than configured manually through the Admin UI.

Blueprint files live in `docker/neo/media-server/authentik/appdata/authentik/blueprints/` and are rendered as Jinja2 templates during deployment. The rendered files are mounted into the container at `/blueprints/custom/`, where Authentik automatically discovers and applies them.

## Architecture

Secrets flow from vault to the running blueprint like this:

```
group_vars/neo/vault.yml
  secret_romm_oidc_client_id: '...'
  secret_romm_oidc_client_secret: '...'
          |
          v
docker/neo/media-server/authentik/.env.j2
  ROMM_OIDC_CLIENT_ID={{ secret_romm_oidc_client_id }}
  ROMM_OIDC_CLIENT_SECRET={{ secret_romm_oidc_client_secret }}
          |
          v (Ansible renders .env.j2 → /opt/docker/compose/media-server/authentik/.env)
          |
          v (Docker Compose passes env file to container)
          |
          v
authentik/blueprints/romm.yml
  client_id: !Env ROMM_OIDC_CLIENT_ID   ← Authentik reads from container env at runtime
  client_secret: !Env ROMM_OIDC_CLIENT_SECRET
```

The `!Env` YAML tag is an Authentik blueprint extension that reads a value from the container's environment at the time the blueprint is applied.

## Adding a New App

### 1. Generate secrets

```bash
# Client ID — a short human-readable identifier is fine, or generate a random one
echo "myapp"

# Client secret — must be a strong random value
openssl rand -hex 32
```

### 2. Add secrets to vault

```bash
make vault-unlock
```

Add to `group_vars/neo/vault.yml`:

```yaml
secret_myapp_oidc_client_id: 'myapp'
secret_myapp_oidc_client_secret: '<generated value>'
```

```bash
make vault-lock
```

### 3. Add env vars to `.env.j2`

In `docker/neo/media-server/authentik/.env.j2`, append:

```
MYAPP_OIDC_CLIENT_ID={{ secret_myapp_oidc_client_id }}
MYAPP_OIDC_CLIENT_SECRET={{ secret_myapp_oidc_client_secret }}
```

### 4. Create the blueprint

Create `docker/neo/media-server/authentik/appdata/authentik/blueprints/myapp.yml.j2`:

```yaml
version: 1
metadata:
  name: MyApp OIDC

entries:
  - model: authentik_providers_oauth2.oauth2provider
    id: myapp-provider
    state: present
    identifiers:
      name: myapp
    attrs:
      name: myapp
      client_type: confidential
      client_id: !Env MYAPP_OIDC_CLIENT_ID
      client_secret: !Env MYAPP_OIDC_CLIENT_SECRET
      redirect_uris:
        - url: "https://myapp.{{ secret_domain }}/callback"
          matching_mode: strict  # or: startswith, regex
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
      signing_key: !Find [authentik_crypto.certificatekeypair, [name, "authentik Self-signed Certificate"]]
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, openid]]
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, email]]
        - !Find [authentik_providers_oauth2.scopemapping, [scope_name, profile]]

  - model: authentik_core.application
    state: present
    identifiers:
      slug: myapp
    attrs:
      name: MyApp
      slug: myapp
      provider: !KeyOf myapp-provider
      policy_engine_mode: any
```

**Redirect URI matching modes:**
- `strict` — exact match (use for most apps)
- `startswith` — prefix match (use when the app appends dynamic segments, e.g. Gramps)
- `regex` — full regex match

### 5. Deploy

```bash
make neo-docker
```

The Ansible compose role will render the blueprint template to the appdata path, which is bind-mounted into the container. Authentik's worker picks up new/changed blueprints automatically.

## Verification

Check that Authentik applied the blueprint without errors:

```bash
docker logs authentik-worker 2>&1 | grep -i "blueprint\|error\|myapp"
```

Or via Loki:

```bash
SERVICE=authentik-worker
curl -G -s "http://192.168.1.3:3100/loki/api/v1/query_range" \
  --data-urlencode "query={container_name=\"/${SERVICE}\"} |~ \"(?i)blueprint\"" \
  --data-urlencode "start=$(date -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode "limit=50" \
  | jq -r '.data.result[].values[][1]'
```

In the Authentik Admin UI (`https://auth.<domain>/if/admin/`):
- **Applications** — the new app should appear with a linked provider
- **Providers** — the OAuth2 provider should show the correct client ID and redirect URI

## Managed Blueprints

| Blueprint file | App | Redirect URI | Matching mode |
|---|---|---|---|
| `romm.yml.j2` | RomM | `https://romm.<domain>/api/oauth/openid` | strict |
| `gramps.yml.j2` | Gramps | `https://gramps.<domain>/api/oidc/callback/` | startswith |
| `freshrss.yml.j2` | FreshRSS | `https://rss.<domain>/i/?oidc_callback=1` | strict |
