#!/bin/bash
# Pulls the latest demo-app image and replaces the running container with
# it -- old container removed, old (now-untagged) image layers pruned,
# fresh one started in its place.
#
# Deliberately bypasses Portainer's own stack deploy: its registry-auth
# injection for this raw-YAML stack proved unreliable in practice (401s
# even with confirmed-correct credentials sitting in its Registries
# config), where a direct CLI pull + recreate has worked every time it's
# been tried. See docs/demo-app.md for the full account.
set -euo pipefail

DOMAIN="${DOMAIN:-deploymentportal.in}"
IMAGE="registry.${DOMAIN}/demo/forge-stack-demo-app:latest"
CONTAINER="forge-stack-demo-app-demo-app-1"
NETWORK="forge-edge"

echo "==> Pulling latest image"
docker pull "$IMAGE"

echo "==> Removing old container (if any)"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

echo "==> Pruning old, now-untagged image layers"
docker image prune -f >/dev/null

echo "==> Starting new container"
docker run -d \
	--name "$CONTAINER" \
	--network "$NETWORK" \
	--restart unless-stopped \
	--label traefik.enable=true \
	--label "traefik.http.routers.demo-app.rule=Host(\`demo.${DOMAIN}\`)" \
	--label traefik.http.routers.demo-app.entrypoints=websecure \
	--label traefik.http.routers.demo-app.tls.certresolver=le \
	--label traefik.http.services.demo-app.loadbalancer.server.port=3000 \
	"$IMAGE" >/dev/null

echo "==> Done"
docker ps --filter "name=$CONTAINER" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
