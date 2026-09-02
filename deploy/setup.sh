#!/bin/bash
# One-shot bootstrap: clone the repo, run this, and everything that CAN be
# automated is. What's left afterward is inherent to five tools' own
# first-run wizards (Forgejo, Woodpecker, SonarQube, Harbor, Portainer each
# require at least one interactive step the first time) -- this script
# prints exactly what those are and in what order, once the base stack is
# healthy.
#
# Usage:
#   ./setup.sh <domain>          # e.g. ./setup.sh localhost
#   ./setup.sh                   # prompts for the domain interactively
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- prerequisites
log "Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "Docker is not installed. See https://get.docker.com"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose plugin not found."; exit 1; }
echo "Docker + Compose: OK"

current_map_count="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
if [ "$current_map_count" -lt 262144 ]; then
	log "Raising vm.max_map_count (required for SonarQube's embedded Elasticsearch)"
	sudo sysctl -w vm.max_map_count=262144
	grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null || echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
else
	echo "vm.max_map_count already sufficient ($current_map_count)"
fi

# ---------------------------------------------------------------- domain
DOMAIN="${1:-${DOMAIN:-}}"
if [ -z "$DOMAIN" ]; then
	read -rp "Domain (use 'localhost' for a local/no-DNS test deployment): " DOMAIN
fi

USE_TLS=false
COMPOSE_FILES="-f docker-compose.yml"
if [ "$DOMAIN" != "localhost" ]; then
	USE_TLS=true
	COMPOSE_FILES="-f docker-compose.yml -f docker-compose.tls.yml"
	warn "DOMAIN=$DOMAIN — make sure every required subdomain (forgejo, ci, sonar, ops, storage, storage-console, grafana, traefik, registry, demo) already resolves to this host's public IP before continuing, or Traefik will hit Let's Encrypt's rate limit retrying unresolved records. See deploy/README.md for the exact record list."
	read -rp "DNS confirmed and propagated? [y/N] " dns_ok
	[ "$dns_ok" = "y" ] || [ "$dns_ok" = "Y" ] || { echo "Fix DNS first, then re-run this script."; exit 1; }
fi

# ---------------------------------------------------------------- .env generation
if [ -f .env ]; then
	warn ".env already exists — leaving it untouched. Delete it first if you want fresh secrets generated."
else
	log "Generating .env with random secrets"
	# Alphanumeric only, deliberately: every credential-escaping bug hit
	# building this platform traced back to a literal '$' in a password
	# getting mangled by some layer of templating (Compose's own
	# interpolation, or Harbor's `prepare` step). Avoiding '$' entirely
	# sidesteps the whole class of bug for every secret except the one
	# that structurally requires it below.
	genpass() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }

	cp .env.example .env

	sed -i "s|^DOMAIN=.*|DOMAIN=${DOMAIN}|" .env
	sed -i "s|^ACME_EMAIL=.*|ACME_EMAIL=admin@${DOMAIN}|" .env

	sed -i "s|^POSTGRES_SUPERUSER_PASSWORD=.*|POSTGRES_SUPERUSER_PASSWORD=$(genpass)|" .env
	sed -i "s|^FORGEJO_DB_PASSWORD=.*|FORGEJO_DB_PASSWORD=$(genpass)|" .env
	sed -i "s|^SONARQUBE_DB_PASSWORD=.*|SONARQUBE_DB_PASSWORD=$(genpass)|" .env
	sed -i "s|^WOODPECKER_AGENT_SECRET=.*|WOODPECKER_AGENT_SECRET=$(genpass)|" .env
	sed -i "s|^WOODPECKER_GRPC_SECRET=.*|WOODPECKER_GRPC_SECRET=$(genpass)|" .env
	sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=$(genpass)|" .env
	sed -i "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=$(genpass)|" .env

	# The Traefik dashboard password is the one credential that structurally
	# needs '$' (it's a bcrypt/apr1 hash) -- generate it and escape it
	# programmatically instead of leaving that to a human to get right by
	# hand, which is exactly what went wrong the first time.
	traefik_pass="$(genpass)"
	traefik_hash="$(openssl passwd -apr1 -salt "$(openssl rand -hex 4)" "$traefik_pass")"
	traefik_hash_escaped="$(printf '%s' "$traefik_hash" | sed 's/\$/\$\$/g')"
	sed -i "s|^TRAEFIK_DASHBOARD_AUTH=.*|TRAEFIK_DASHBOARD_AUTH=admin:${traefik_hash_escaped}|" .env

	# WOODPECKER_ADMIN needs a real Forgejo username, which doesn't exist
	# yet -- leave it blank, filled in during the manual steps below.

	{
		echo ""
		echo "===================================================================="
		echo "  GENERATED CREDENTIALS -- save these now, they will not be shown again"
		echo "===================================================================="
		echo "  Traefik dashboard:  admin / ${traefik_pass}"
		echo "  All other generated passwords are in .env -- back that file up"
		echo "  somewhere safe (it's gitignored, and rightly so)."
		echo "===================================================================="
	} | tee .env.CREDENTIALS.txt
	warn "Credentials also written to .env.CREDENTIALS.txt -- read it now, then delete it."
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

# ---------------------------------------------------------------- bring up the base stack, in dependency order
log "Starting Traefik + Postgres"
# shellcheck disable=SC2086
docker compose $COMPOSE_FILES up -d traefik postgres

log "Waiting for Postgres to be healthy"
# shellcheck disable=SC2086
until docker compose $COMPOSE_FILES exec -T postgres pg_isready -U "${POSTGRES_SUPERUSER}" >/dev/null 2>&1; do
	printf '.'
	sleep 2
done
echo " ready"

log "Starting Forgejo, SonarQube, Portainer, MinIO, observability, and the backup job"
# shellcheck disable=SC2086
docker compose $COMPOSE_FILES up -d forgejo sonarqube portainer minio \
	node-exporter cadvisor prometheus loki promtail grafana backup

log "Waiting for Forgejo to respond"
scheme="http"
[ "$USE_TLS" = true ] && scheme="https"
forgejo_url="${scheme}://forgejo.${DOMAIN}"
tries=0
until curl -sk -o /dev/null "$forgejo_url" || [ $tries -ge 30 ]; do
	printf '.'
	sleep 2
	tries=$((tries + 1))
done
echo ""

# ---------------------------------------------------------------- what's left
cat <<EOF

====================================================================
  Base stack is up. What's left is inherent to five tools' own
  first-run flows -- none of it skippable, all of it quick.
====================================================================

1. Forgejo — complete the install screen, then create your account:
     ${forgejo_url}/

2. Register Woodpecker as an OAuth app in Forgejo (Settings ->
   Applications -> Manage OAuth2 Applications), redirect URI
   https://ci.${DOMAIN}/authorize (or http:// if DOMAIN=localhost),
   then put the client ID/secret into .env as WOODPECKER_FORGEJO_CLIENT
   / WOODPECKER_FORGEJO_SECRET, your Forgejo username into
   WOODPECKER_ADMIN, and bring it up:
     docker compose $COMPOSE_FILES up -d woodpecker-server woodpecker-agent

3. SonarQube (${scheme}://sonar.${DOMAIN}/) — log in
   (admin/admin, forced change), generate a token, store it as a
   Woodpecker secret named SONAR_TOKEN for any repo whose pipeline
   needs it.

4. Harbor — separate installer, not part of this script. Full steps:
     deploy/harbor/README.md

5. Portainer (${scheme}://ops.${DOMAIN}/) — set the initial
   admin account (it self-locks after a few minutes if you wait too
   long -- restart the container to re-open the window if you miss it).

Full access-URL table and troubleshooting for anything above:
  deploy/README.md
  https://github.com/VarshithChand/Open-Source-Infra-Managemanet/wiki/Real-World-Gotchas
EOF
