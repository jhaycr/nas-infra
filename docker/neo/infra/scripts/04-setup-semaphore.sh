#!/usr/bin/env bash
# Run this script from trinity (or any host that can reach neo) after the infra
# stack is deployed. Configures Semaphore via API: project, keys, repo, inventory,
# and task template.
#
# Requires: curl, jq
set -euo pipefail

SEMAPHORE_URL="http://192.168.1.3:3030"
REPO_ROOT="$(git rev-parse --show-toplevel)"
VAULT_KEY_FILE="$(dirname "$REPO_ROOT")/.ansible-vault.key"
COOKIE_JAR=$(mktemp)
NEO_USER="user0"
REPO_PATH="/home/$NEO_USER/code/gitea-working-clones/nas-infra"

cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup EXIT

die() { echo "Error: $*" >&2; exit 1; }

api() {
  local method="$1" path="$2"; shift 2
  curl -sf -b "$COOKIE_JAR" -X "$method" "$SEMAPHORE_URL/api$path" \
    -H "Content-Type: application/json" "$@"
}

# --- Vault key content ---
if [ ! -f "$VAULT_KEY_FILE" ]; then
  read -rsp "Paste vault key contents: " VAULT_KEY_CONTENT; echo
else
  VAULT_KEY_CONTENT=$(cat "$VAULT_KEY_FILE")
  echo "Using vault key from $VAULT_KEY_FILE"
fi

# --- Login ---
echo "=== Logging in to Semaphore ==="
read -rsp "Semaphore admin password: " SEMAPHORE_PASS; echo

curl -sf -c "$COOKIE_JAR" -X POST "$SEMAPHORE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"auth\": \"admin\", \"password\": \"$SEMAPHORE_PASS\"}" > /dev/null \
  || die "Login failed — check password and that Semaphore is running"

echo "  Logged in."

# --- Project ---
echo "=== Creating project ==="
PROJECT=$(api POST /projects \
  -d '{"name": "nas-infra", "alert": false, "alert_chat": "", "max_parallel_tasks": 0}')
PROJECT_ID=$(echo "$PROJECT" | jq -r '.id')
echo "  Project ID: $PROJECT_ID"

# --- Keys ---
echo "=== Creating key store entries ==="

NONE_KEY=$(api POST "/project/$PROJECT_ID/keys" \
  -d "{\"name\": \"none\", \"type\": \"none\", \"project_id\": $PROJECT_ID}")
NONE_KEY_ID=$(echo "$NONE_KEY" | jq -r '.id')
echo "  none key ID: $NONE_KEY_ID"

VAULT_KEY=$(api POST "/project/$PROJECT_ID/keys" \
  -d "$(jq -n \
    --arg name "vault-key" \
    --arg pass "$VAULT_KEY_CONTENT" \
    --argjson pid "$PROJECT_ID" \
    '{name: $name, type: "login_password", project_id: $pid,
      login_password: {login: "", password: $pass}}')")
VAULT_KEY_ID=$(echo "$VAULT_KEY" | jq -r '.id')
echo "  vault-key ID: $VAULT_KEY_ID"

# --- Repository ---
echo "=== Creating repository ==="
REPO=$(api POST "/project/$PROJECT_ID/repositories" \
  -d "$(jq -n \
    --arg path "$REPO_PATH" \
    --argjson pid "$PROJECT_ID" \
    --argjson kid "$NONE_KEY_ID" \
    '{name: "nas-infra", project_id: $pid, git_url: $path,
      git_branch: "main", ssh_key_id: $kid}')")
REPO_ID=$(echo "$REPO" | jq -r '.id')
echo "  Repository ID: $REPO_ID"

# --- Inventory ---
echo "=== Creating inventory ==="
INVENTORY=$(api POST "/project/$PROJECT_ID/inventory" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson kid "$NONE_KEY_ID" \
    '{name: "neo-local", project_id: $pid, type: "static",
      inventory: "localhost ansible_connection=local",
      ssh_key_id: $kid, become_key_id: $kid}')")
INVENTORY_ID=$(echo "$INVENTORY" | jq -r '.id')
echo "  Inventory ID: $INVENTORY_ID"

# --- Task template ---
echo "=== Creating task template ==="
api POST "/project/$PROJECT_ID/templates" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson rid "$REPO_ID" \
    --argjson iid "$INVENTORY_ID" \
    --argjson vkid "$VAULT_KEY_ID" \
    '{name: "Deploy neo (compose)", project_id: $pid,
      playbook: "site.yml",
      arguments: "[\"--tags\", \"compose\", \"--limit\", \"neo\"]",
      repository_id: $rid, inventory_id: $iid,
      vault_key_id: $vkid, type: "task"}')" > /dev/null
echo "  Template created."

echo ""
echo "Done. Semaphore is fully configured."
echo "  UI: $SEMAPHORE_URL"
echo ""
echo "Next steps:"
echo "  1. Run 05-setup-trinity.sh"
echo "  2. Run the 'Deploy neo (compose)' template once to verify end-to-end."
