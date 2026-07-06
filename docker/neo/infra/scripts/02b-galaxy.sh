#!/usr/bin/env bash
# Installs Galaxy roles inside the semaphore container.
#
# NOTE: This script is NOT required for Semaphore's compose-only deployments
# (make neo-docker / --tags compose). The docker_compose role is local and
# ansible_collections/ is already committed to the repo.
#
# Only run this if you need full site.yml runs (disk setup, system config, etc.)
# from Semaphore, which require Galaxy roles like geerlingguy.docker.
#
# Run from trinity AFTER 'make neo-docker' has started the semaphore container.
set -euo pipefail

NEO_USER="user0"
NEO_HOST="neo"
NEO_REPO_DIR="/home/$NEO_USER/code/gitea-working-clones/nas-infra"
GALAXY_BIN="/opt/semaphore/apps/ansible/11.1.0/venv/bin/ansible-galaxy"

echo "=== [neo] Installing Galaxy roles inside semaphore container ==="
echo "  (will prompt for sudo password on neo)"

ssh -t "$NEO_USER@$NEO_HOST" \
  "sudo docker inspect semaphore --format '{{.State.Status}}' 2>/dev/null | grep -q running \
   || { echo 'ERROR: semaphore not running — run make neo-docker first'; exit 1; } && \
   sudo docker exec semaphore test -f '$NEO_REPO_DIR/requirements.yml' \
   || { echo 'ERROR: requirements.yml missing — ensure the working clone is populated'; exit 1; } && \
   echo 'Installing roles...' && \
   sudo docker exec semaphore $GALAXY_BIN role install \
     -r '$NEO_REPO_DIR/requirements.yml' \
     --roles-path '$NEO_REPO_DIR/roles' \
     --force"

echo ""
echo "Done. Next steps:"
echo "  1. Complete the Gitea setup wizard at http://192.168.1.3:3105"
echo "  2. Run scripts/03-setup-gitea.sh"
