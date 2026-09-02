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

**Avoid `$` in both passwords.** Confirmed the hard way: Harbor's `prepare` step passes these through its own templating before they reach the running containers, and a literal `$` got mangled somewhere in that chain — the admin login silently stopped matching what was in `harbor.yml`, even immediately after a fresh install with a verified-correct file. Cost two full reinstall cycles to isolate. Simplest fix, and the one actually used: generate passwords without `$` for these two fields specifically. (This is a different, harder-to-diagnose failure mode than the well-known Compose `$$`-escaping issue — that one at least gives a clear signal via `docker compose config`; this one doesn't.)

## 3. Install

```bash
sudo ./install.sh --with-trivy
```

This generates `docker-compose.yml` in this directory and starts Harbor's own service set, including Trivy for the CVE scanning referenced throughout the docs.

**`install.sh` re-runs `prepare` and regenerates `docker-compose.yml` from `harbor.yml` every time**, including on a second run against an already-initialized instance. Two consequences worth knowing before you hit them:

- **Step 4 below (network/label attachment) gets silently reverted** every time you reinstall — the generated file has no idea `forge-edge` or Traefik labels exist. Redo step 4 after any reinstall.
- **A password change in `harbor.yml` does *not* reset an already-initialized database.** Harbor's Postgres data lives on a host **bind mount** (`data_volume` in `harbor.yml`, default `/data`), not a Docker-managed volume — `docker compose down -v` has zero effect on it, and Postgres only applies `POSTGRES_PASSWORD` on a genuinely empty data directory. If you need to actually change the admin/DB password after a first install, `down` (no `-v` needed, it wouldn't help anyway) and `rm -rf <data_volume>/database` on the host *before* reinstalling — otherwise every subsequent install silently keeps the original first-ever password no matter what the file says.

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

**Also close off the direct host exposure.** `http.port: 8081` in `harbor.yml` makes Harbor's generated compose file publish that port straight to the host (`0.0.0.0:8081->8080`), bypassing Traefik entirely — a second, unauthenticated-by-Traefik path into the registry. Comment out that `ports:` block in the generated `docker-compose.yml` (it's on the `proxy` service) and recreate it:

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --force-recreate proxy
```

Remember this comes back every time `install.sh` reruns, same as the network attachment above.

## 5. Wire it into the pipeline

- The build step in a repo's `.woodpecker.yml` pushes to `registry.${DOMAIN}/<project>/<image>` using the `woodpeckerci/plugin-docker-buildx` image (see [`demo-app/.woodpecker.yml`](../../demo-app/.woodpecker.yml) for a real, working example) — create a robot account in Harbor's UI (**Projects → \<project\> → Robot Accounts**, grant Pull + Push) and store its credentials as Woodpecker secrets (`docker_username` / `docker_password`), rather than using the admin account.
- **Copy the robot account's full name exactly as Harbor displays it — don't assume the format.** Harbor's documented convention is `robot$<project>+<name>`, but what actually got created here was `robot$<name>`, no project prefix. Assuming the documented pattern instead of checking cost real debugging time.
- **Building Docker images from a pipeline needs one more server-side setting**: Woodpecker 3.x runs plugins unprivileged by default, and `docker-buildx` needs privileged execution. Without `WOODPECKER_PLUGINS_PRIVILEGED: woodpeckerci/plugin-docker-buildx` set on `woodpecker-server` (already in this repo's `deploy/docker-compose.yml`), the build step fails at lint time with "formerly privileged plugin ... no longer privileged by default."
- If a robot account's token is ever refreshed (Harbor → Robot Accounts → Refresh secret), update the `docker_password` Woodpecker secret immediately — the old token stops working the instant the new one is generated, and the next build fails with an authentication error at the `docker login` step.
- Add the commented-out `harbor` job in `deploy/prometheus/prometheus.yml` once `harbor-core` is reachable, so registry/scan metrics show up in Grafana alongside everything else.
