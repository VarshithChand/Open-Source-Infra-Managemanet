# Deploying Forge Stack

This brings up every service except Harbor (installed separately — see [harbor/README.md](harbor/README.md)) with one `docker compose up`. It works unmodified against either target:

| | Local (Docker Desktop) | VM with a domain |
|---|---|---|
| `DOMAIN` | `localhost` | your real domain, e.g. `example.com` |
| Compose files | `docker-compose.yml` only | `docker-compose.yml` **+** `docker-compose.tls.yml` |
| TLS | none — plain HTTP | automatic, via Let's Encrypt |
| DNS | none needed — `*.localhost` resolves to `127.0.0.1` on its own | A records for each subdomain below pointed at the VM's IP |
| Ports to open | none (all local) | 80 and 443 |

## Prerequisites

- Docker Engine 25+ and the Compose plugin
- On a Linux host: `vm.max_map_count` must be raised for SonarQube's embedded Elasticsearch —
  ```bash
  sudo sysctl -w vm.max_map_count=262144
  # persist it:
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
  ```
  (Docker Desktop's Linux VM already ships with this set — nothing to do locally.)
- At least 8 GB RAM free for the base stack; SonarQube alone wants ~2 GB.

## 1. Configure

```bash
cd deploy
cp .env.example .env
```

Edit `.env`: set `DOMAIN`, replace every `change-me-*` password, and generate a real Traefik dashboard hash:

```bash
htpasswd -nB admin
# paste the result into TRAEFIK_DASHBOARD_AUTH, doubling every '$' to '$$'
```

Leave `WOODPECKER_FORGEJO_CLIENT` / `WOODPECKER_FORGEJO_SECRET` blank for now — they don't exist until step 3.

## 2. Bring up everything except Woodpecker

Forgejo has to exist before Woodpecker can authenticate against it, so bring the rest of the stack up first:

```bash
docker compose up -d traefik postgres forgejo sonarqube portainer minio \
  node-exporter cadvisor prometheus loki promtail grafana
```

```bash
# VM deployment instead:
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d \
  traefik postgres forgejo sonarqube portainer minio \
  node-exporter cadvisor prometheus loki promtail grafana
```

Watch `docker compose logs -f forgejo` until it reports it's listening, then open `http://forgejo.<DOMAIN>/` and complete the first-run install screen (it pre-fills the Postgres connection from the environment — just set the admin account).

## 3. Register Woodpecker as an OAuth app in Forgejo

In Forgejo: **Settings → Applications → Manage OAuth2 Applications → Create a new OAuth2 Application**

- Name: `Woodpecker CI`
- Redirect URI: `http://ci.<DOMAIN>/authorize` (or `https://` on a VM)

Copy the generated **Client ID** and **Client Secret** into `.env` as `WOODPECKER_FORGEJO_CLIENT` / `WOODPECKER_FORGEJO_SECRET`, then start Woodpecker:

```bash
docker compose up -d woodpecker-server woodpecker-agent
```

Open `http://ci.<DOMAIN>/` and sign in with **Login via Forgejo** — this is the OAuth flow you just registered.

## 4. Generate a SonarQube token

Log into `http://sonar.<DOMAIN>/` (default `admin` / `admin`, changed on first login), then **My Account → Security → Generate Token**. Store it as a Woodpecker secret (`SONAR_TOKEN`) on whichever repo's pipeline runs the quality-gate step from `docs/setup.md`.

## 5. Install Harbor

Follow [harbor/README.md](harbor/README.md) — it's a separate installer that then joins the same `forge-edge` network Traefik already watches.

## Access URLs

Once everything is up (`<domain>` = `localhost` locally, or your real domain on a VM):

| Service | URL | First login |
|---|---|---|
| Forgejo | `http://forgejo.<domain>/` | set during first-run install |
| Woodpecker CI | `http://ci.<domain>/` | via "Login with Forgejo" |
| SonarQube | `http://sonar.<domain>/` | `admin` / `admin` (forced change) |
| Harbor | `http://registry.<domain>/` | `admin` / value of `harbor_admin_password` |
| Portainer | `http://ops.<domain>/` | set on first visit |
| MinIO console | `http://storage-console.<domain>/` | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| Grafana | `http://grafana.<domain>/` | `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` |
| Traefik dashboard | `http://traefik.<domain>/` | `TRAEFIK_DASHBOARD_AUTH` credentials |

On a VM deployment, swap `http://` for `https://` — the TLS overlay redirects port 80 to 443 automatically.

## Bringing it down

```bash
docker compose down          # stop, keep volumes (all data persists)
docker compose down -v       # stop and delete all data — start over clean
```
