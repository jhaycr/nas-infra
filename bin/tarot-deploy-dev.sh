#!/usr/bin/env bash
# Build the local tarot working tree and run it on neo WITHOUT publishing to ghcr.
#
# Builds ~/Code/tarot (or $1) as ghcr.io/jhaycr/tarot:dev, streams it to neo via
# docker save/load, and redeploys the stack pinned to the dev tag. Return to the
# released version afterwards with a plain `make neo-docker`.
set -euo pipefail

REPO="${1:-$HOME/Code/tarot}"
cd "$(dirname "$0")/.."

# Stamp the dev image with the working-tree state so the in-app version line
# tells you exactly which local build is live on neo (e.g. dev-201ba30-dirty).
DEV_VERSION="dev-$(git -C "$REPO" describe --always --dirty --exclude '*' 2>/dev/null || echo local)"
echo "Building $DEV_VERSION"

docker --context default build --build-arg TAROT_VERSION="$DEV_VERSION" \
  -t ghcr.io/jhaycr/tarot:dev "$REPO"
docker --context default save ghcr.io/jhaycr/tarot:dev | gzip > /tmp/tarot-dev.tar.gz
ansible neo -m copy -a "src=/tmp/tarot-dev.tar.gz dest=/tmp/tarot-dev.tar.gz"
ansible neo --become -m shell -a "gunzip -c /tmp/tarot-dev.tar.gz | docker load && rm /tmp/tarot-dev.tar.gz"
rm -f /tmp/tarot-dev.tar.gz

make neo-docker EXTRA_VARS="tarot_image_tag=dev"
