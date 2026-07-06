# Infra Stack Setup

Bootstrap guide for the infra stack on neo: Gitea, Semaphore, and supporting services.

> Most of this is now driven by Ansible roles. The scripts in `docker/neo/infra/scripts/` are kept
> as reference / fallback but are superseded by the roles described below.

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Gitea | `http://192.168.1.3:3105` | Git mirror of `jhaycr/nas-infra` |
| Semaphore | `http://192.168.1.3:3030` | Ansible deployment UI |
| Metrics | — | Prometheus + Grafana + Loki + Alloy |
| VS Code | — | Browser-based editor |
| Dozzle | `http://192.168.1.3:8081` | Container log viewer |

---

## Vault secrets required

Add these to `group_vars/neo/vault.yml` (`make vault-unlock` first):

```yaml
secret_gitea_db_password: <random string>
secret_gitea_admin_password: <gitea admin password set during wizard>
secret_semaphore_admin_password: <strong password>
secret_semaphore_encryption_key: <32 random chars — openssl rand -base64 32 | head -c 32>
```

---

## Step 1 — Bootstrap neo (Ansible)

Runs the `jhaycr-local.infra_bootstrap` role, which:
- Creates directory structure (`~/.secrets/`, `~/code/gitea-working-clones/nas-infra/`, `~/code/gitea-repos/`)
- Copies vault key and vault files from the controller (trinity) to neo
- Clones the nas-infra working copy if not already present
- Configures the working clone to accept direct pushes (`receive.denyCurrentBranch = updateInstead`)

```bash
make neo --tags bootstrap
```

---

## Step 2 — Deploy the infra stack

```bash
make neo-docker
```

Renders all Jinja2 templates and starts the Docker Compose stack (Gitea, Semaphore, Traefik, Metrics, etc.).

---

## Step 3 — Gitea setup wizard (manual, one-time)

Browse to `http://192.168.1.3:3105` and complete the setup wizard:

- Database: PostgreSQL, host `gitea-db:5432`, db/user `gitea`, password from vault
- Admin account: set username and password (store password in vault as `secret_gitea_admin_password`)

---

## Step 4 — Configure Gitea mirrors and Semaphore (Ansible)

```bash
make neo --tags gitea,semaphore
```

- **`jhaycr-local.gitea_mirrors`** — creates orgs (`backup`, `books`) and all 13 pull mirrors from GitHub. Add new mirrors by editing `gitea_mirrors` in `group_vars/neo/vars.yml`.
- **`jhaycr-local.semaphore`** — configures Semaphore with project, keys, repository, inventory, and the `Deploy neo (compose)` task template.

---

## Step 5 — Trinity git remotes (one-time, manual)

Adds `neo` as a git remote on trinity so you can push directly over LAN:

```bash
scripts/05-setup-trinity.sh
```

**Online workflow:**
```bash
git push origin main        # → GitHub → Gitea mirrors automatically
```

**Offline/LAN-only workflow:**
```bash
git push neo main           # → neo directly; Semaphore picks it up immediately
```

---

## Verify

- Gitea: `http://192.168.1.3:3105`
- Semaphore: `http://192.168.1.3:3030`
- Logs: Dozzle at `http://192.168.1.3:8081`
  - Check `semaphore`, `gitea-server`, `gitea-db`
- In Semaphore, run `Deploy neo (compose)` → confirm Ansible completes successfully

---

## Re-provisioning from scratch

```bash
make neo --tags bootstrap        # dirs, vault, working clone
make neo-docker                  # deploy stack
# complete Gitea wizard manually
make neo --tags gitea,semaphore  # configure services
scripts/05-setup-trinity.sh      # add neo git remote (if not already set)
```
