# Installing Harbor

Harbor isn't a single container — its own installer generates a multi-service `docker-compose.yml` (core, portal, registry, jobservice, trivy, redis, its own Postgres, and an nginx front door) from a `harbor.yml` config file. Hand-rolling that into the main stack's compose file would fight Harbor's own lifecycle tooling, so it's installed here as its own unit and then joined to the shared `forge-edge` network so Traefik can route to it like everything else.

## 1. Download the installer

```bash
cd deploy/harbor
curl -LO https://github.com/goharbor/harbor/releases/download/v2.15.2/harbor-offline-installer-v2.15.2.tgz
tar xzf harbor-offline-installer-v2.15.2.tgz --strip-components=1
```

Check [Harbor's releases page](https://github.com/goharbor/harbor/releases) for whatever the current stable tag is before pulling — pin to that instead of trusting this number to stay current.

## 2. Configure `harbor.yml`

Copy the template and edit the essentials:

```bash
cp harbor.yml.tmpl harbor.yml
```

```yaml
# harbor.yml — key fields to change
hostname: registry.${DOMAIN}      # e.g. registry.localhost or registry.example.com

http:
  port: 8081                      # avoid Traefik's own :80 on the host

# Local (no TLS) deployment: delete the whole `https:` block.
# VM deployment: point https.certificate / https.private_key at real certs,
# or terminate TLS at Traefik instead and leave Harbor on http internally
# (recommended — keeps certificate management in one place, see step 4).

harbor_admin_password: <set a real password>
database:
  password: <set a real password>
```

## 3. Install

```bash
sudo ./install.sh --with-trivy
```

This generates `docker-compose.yml` in this directory and starts Harbor's own service set, including Trivy for the CVE scanning referenced throughout the docs.

## 4. Attach Harbor to the shared edge network

Harbor's generated compose file is self-contained and doesn't know about `forge-edge`. Add the network to its **proxy** (nginx) service and give it Traefik labels — either by editing `deploy/harbor/docker-compose.yml` directly, or with an override file:

```yaml
# deploy/harbor/docker-compose.override.yml
services:
  proxy:
    networks:
      - default
      - forge-edge
    labels:
      - traefik.enable=true
      - traefik.http.routers.harbor.rule=Host(`registry.${DOMAIN}`)
      - traefik.http.services.harbor.loadbalancer.server.port=8080
      # VM deployment — add the same two lines used elsewhere in docker-compose.tls.yml:
      # - traefik.http.routers.harbor.entrypoints=websecure
      # - traefik.http.routers.harbor.tls.certresolver=le

networks:
  forge-edge:
    external: true
```

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
```

## 5. Wire it into the pipeline

- Woodpecker's `plugins/docker` step (see `docs/setup.md`) pushes to `registry.${DOMAIN}/<project>/<image>` — create a robot account in Harbor's UI (**Projects → \<project\> → Robot Accounts**) and store its credentials as Woodpecker secrets (`DOCKER_USERNAME` / `DOCKER_PASSWORD`), rather than using the admin account.
- Add the commented-out `harbor` job in `deploy/prometheus/prometheus.yml` once `harbor-core` is reachable, so registry/scan metrics show up in Grafana alongside everything else.
