# Setup Approach

The stack is deployable as-is — real, working configuration lives in [`deploy/`](../deploy/), not just illustrative snippets. This document explains the shape of that deployment; for the actual step-by-step bring-up, see [`deploy/README.md`](../deploy/README.md).

## Deployment model

- **Host**: a single Docker host is enough to run the full stack for a small team — Docker Desktop locally, or any Linux VM with Docker Engine + the Compose plugin.
- **One compose file, two targets**: [`deploy/docker-compose.yml`](../deploy/docker-compose.yml) runs unmodified against `DOMAIN=localhost` for a local deployment. Layering [`deploy/docker-compose.tls.yml`](../deploy/docker-compose.tls.yml) on top adds a `websecure` entrypoint and automatic Let's Encrypt certificates for a VM deployment with a real domain — see the comparison table in `deploy/README.md`.
- **Networking**: two Docker networks — `forge-edge` (everything Traefik routes to) and `forge-internal` (databases and other backends, marked `internal: true` so they have no route out to the host or the internet).
- **Database**: Forgejo and SonarQube share one Postgres container, each with its own database and role, created on first boot by [`deploy/postgres/init-multiple-databases.sh`](../deploy/postgres/init-multiple-databases.sh) — one fewer container to operate than a database-per-service layout, without either service's data mixing with the other's.
- **State**: every service's data directory is a named Docker volume; nightly dumps get pushed to MinIO (see [Backups](#backups)).
- **Domains**: one subdomain per service behind `${DOMAIN}` — `forgejo.`, `ci.`, `sonar.`, `registry.`, `ops.`, `storage.`, `grafana.`, `traefik.` — all resolved to the host, all routed by Traefik. The full URL table is in `deploy/README.md`.
- **Observability sources**: `node-exporter` (host metrics) and `cadvisor` (per-container metrics) are included so Prometheus has real targets to scrape from the moment the stack is up, not just each service's own `/metrics` endpoint.

## What's in `deploy/`

```
deploy/
├── README.md                    quickstart: configure → bring up → bootstrap OAuth → access URLs
├── docker-compose.yml            base stack — traefik, postgres, forgejo, woodpecker,
│                                  sonarqube, portainer, minio, prometheus + grafana + loki + promtail
├── docker-compose.tls.yml        overlay: HTTPS entrypoint + Let's Encrypt, for a VM deployment
├── .env.example                  every credential and domain setting, documented inline
├── postgres/init-multiple-databases.sh
├── prometheus/prometheus.yml
├── loki/loki-config.yaml
├── promtail/promtail-config.yaml
├── grafana/provisioning/datasources/datasources.yaml   (Prometheus + Loki wired in automatically)
└── harbor/README.md              Harbor's own installer + how to join it to the shared network
```

Harbor is deliberately not in the main compose file — its own installer generates a multi-container `docker-compose.yml` from a `harbor.yml` config (core, portal, registry, jobservice, Trivy, its own Postgres, and an nginx front door). Hand-rolling that into the main stack would fight Harbor's lifecycle tooling, so it's installed as its own unit and then joined to the same `forge-edge` network Traefik already watches. Full steps: [`deploy/harbor/README.md`](../deploy/harbor/README.md).

## CI pipeline — a real, working example

[`demo-app/.woodpecker.yml`](../demo-app/.woodpecker.yml) is not a hand-written illustration — it's the actual pipeline file for the sample app that proves this platform's CI/CD path, verified working end to end (test → SonarQube quality gate → build → push to Harbor, Trivy-scanned). Two details worth calling out if you're writing your own from scratch:

- **`woodpeckerci/plugin-docker-buildx`**, not the older `plugins/docker` — and it needs `WOODPECKER_PLUGINS_PRIVILEGED` set on the server (already in `deploy/docker-compose.yml`) or the build step fails at lint time.
- Secret names are **lowercase** (`SONAR_TOKEN` is the one exception, kept uppercase to match what actually got created — Woodpecker secret names are whatever you named them, no forced casing, so just be consistent between where you create them and where `.woodpecker.yml` references them).

The `deploy` step (Portainer redeploy) is deliberately commented out in that file — see [`demo-app/README.md`](../demo-app/README.md) for why (Portainer Community Edition doesn't support stack webhooks) and what redeploying by hand actually looks like.

## Bootstrap order

Standing the stack up follows a dependency order — this is what `deploy/README.md` walks through:

1. **Traefik + Postgres** — nothing else is reachable, or has anywhere to store data, until these exist
2. **Forgejo** — the source of truth everything else depends on; complete its first-run install screen before continuing
3. **Woodpecker** — needs an OAuth2 application registered in Forgejo first (manual, one-time — Forgejo has no API for this that doesn't require an existing session)
4. **SonarQube** — generate a token once logged in, store it as a Woodpecker secret
5. **Harbor** — installed separately, then registered as Woodpecker's push target via a robot account
6. **Portainer** — deploys the application stack Woodpecker builds and pushes to. Its Community Edition does **not** support stack webhooks (that's a Business Edition feature — confirmed by deploying against it, not assumed from docs); auto-redeploy-on-push needs either upgrading to Business Edition or having the `deploy` pipeline step call Portainer's regular API with an access token instead of a webhook URL.
7. **Prometheus / node-exporter / cadvisor / Loki / Promtail / Grafana** — no dependency on anything above, so these can come up in step 1 alongside Traefik and start capturing data from everything else as it boots
8. **MinIO** — backup target for the `backup` service below

## Backups

The `backup` service ([`deploy/postgres/backup.sh`](../deploy/postgres/backup.sh)) dumps every database on the shared Postgres instance (Forgejo, SonarQube) and uploads each to a versioned MinIO bucket (`db-backups`), giving point-in-time recovery without any external dependency. It runs once immediately on container start — so a fresh deploy has a backup within minutes, not after the first interval elapses — then repeats every `BACKUP_INTERVAL_SECONDS` (default 24h). That's a fixed-duration sleep loop, not wall-clock-pinned like real cron; fine for a reference deployment, worth swapping for actual cron scheduling if backup timing needs to be predictable.

Harbor's own database and Grafana's state aren't covered by this job — Harbor manages its own backup story separately (see [Harbor's docs](https://goharbor.io/docs/) for `harbor-db` backup/restore), and Grafana's SQLite file is low-stakes enough (dashboards are reproducible from the JSON in this repo) that it's not currently backed up.
