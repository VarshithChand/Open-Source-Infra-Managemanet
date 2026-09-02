# Forge Stack Demo App

A minimal, zero-dependency Node.js app whose only job is proving the platform's CI/CD path works end to end — not a real application.

**This is a mirror.** The canonical, actively-developed copy lives in its own repository hosted on the platform's own Forgejo instance (`forgejo.<domain>/<user>/Forge-stack-demo-app`) — that's the repo Woodpecker actually watches and builds from. It's not publicly browsable (the instance requires login), so this folder exists to make the source visible here on GitHub. If you're reading this, treat it as read-only reference; changes happen in the Forgejo repo and get copied here afterward, not the other way around.

## What actually happens on a push

```
git push  →  Forgejo  →  Woodpecker
                             ├─ test            node --test, 3 cases
                             ├─ code-quality     SonarQube quality gate (blocking)
                             └─ build-and-push   image → Harbor, Trivy-scanned
                                                       ↓
                                              manual: docker pull + redeploy
```

The first three stages are fully automatic — a push alone gets you a tested, quality-gated, vulnerability-scanned image sitting in Harbor. The last hop (getting that image actually running) is **manual**, and that's a real, confirmed limitation, not an oversight: Portainer Community Edition doesn't support stack webhooks (that's a paid-tier feature), so there's no automatic trigger from "new image in Harbor" to "container redeployed." The deploy step in `.woodpecker.yml` is commented out for this reason.

Redeploying by hand, once a build lands in Harbor:

```bash
docker pull registry.<domain>/demo/forge-stack-demo-app:latest
docker rm -f forge-stack-demo-app-demo-app-1
docker run -d \
  --name forge-stack-demo-app-demo-app-1 \
  --network forge-edge \
  --restart unless-stopped \
  --label traefik.enable=true \
  --label 'traefik.http.routers.demo-app.rule=Host(`demo.<domain>`)' \
  --label traefik.http.routers.demo-app.entrypoints=websecure \
  --label traefik.http.routers.demo-app.tls.certresolver=le \
  --label traefik.http.services.demo-app.loadbalancer.server.port=3000 \
  registry.<domain>/demo/forge-stack-demo-app:latest
```

This bypasses Portainer's own stack tracking deliberately — its "Update the stack" action proved unreliable at picking up a same-tag image change during testing (didn't recreate the container even after a fresh pull), where a direct `docker rm` + `docker run` worked every time. The equivalent stack definition Portainer's UI actually holds is kept in [`deploy/apps/demo-app/docker-compose.yml`](../deploy/apps/demo-app/docker-compose.yml) for reference/reproducibility, even though redeploys in practice go through the CLI.

## Real gotchas hit building this

- **Harbor robot account naming**: assumed the format would be `robot$<project>+<name>` (Harbor's documented convention) — the account actually created was `robot$<name>`, no project prefix. Cost an hour of 401s across Portainer and `docker login` before checking the literal name Harbor's UI showed instead of assuming the pattern.
- **`docker compose down -v` doesn't touch Harbor's database** — Harbor stores Postgres data on a host bind mount (`data_volume` in `harbor.yml`), not a Docker-managed volume, so `-v` has zero effect on it. A password change in `harbor.yml` followed by `down -v` + reinstall silently keeps the *original* first-ever password, because Postgres only applies `POSTGRES_PASSWORD` on a truly empty data directory. Fix was deleting the bind-mounted directory directly (`rm -rf` on the host path), not relying on `-v`.
- **`$` in a password breaks in more places than you'd think** — burned once already on Traefik's basic-auth hash (Compose re-scans substituted `${VAR}` values for `$` the same as the file itself). Hit a second, different instance of the same class of bug with Harbor's admin password specifically; simplest fix was just not using `$` in that one password rather than chasing which of Harbor's internal templating layers was mangling it.

## Local development

```bash
npm test    # runs the 3-test suite
npm start   # serves on :3000 — GET / (dashboard) and GET /healthz (JSON health check)
```

## Pipeline secrets required (set in Woodpecker)

| Secret | Value |
|---|---|
| `SONAR_TOKEN` | SonarQube user token (My Account → Security → Generate Token) |
| `docker_username` | Harbor robot account's exact full name — copy it from Harbor's UI, don't assume the format |
| `docker_password` | Harbor robot account's token (regenerate and update this secret if the account's token is ever refreshed — the old one stops working immediately) |
