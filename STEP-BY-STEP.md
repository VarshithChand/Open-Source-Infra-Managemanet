# Step by Step — From an Empty VM to a Running Platform

This is the complete path: what size machine to provision, how to install Docker on it, how to bring the platform up, and how to actually reach every service afterward. Every command here has been run for real against a live VM while building this project — not copied from documentation and left untested. Where something broke doing that, it's called out inline rather than glossed over; the full account lives in the [wiki's Real World Gotchas page](https://github.com/VarshithChand/Open-Source-Infra-Managemanet/wiki/Real-World-Gotchas).

---

## 1. Provision the VM

### Sizing

| Resource | Minimum | Comfortable (recommended) |
|---|---|---|
| vCPU | 4 | 4–8 |
| RAM | 16 GB | 16–32 GB |
| Disk | 128 GB SSD | 128 GB SSD |
| OS | Ubuntu Server 24.04 LTS | Ubuntu Server 24.04 LTS |

**Why 16GB is the real floor, not just a round number**: SonarQube's bundled Elasticsearch alone wants ~2GB, Harbor's own install docs call for 4GB minimum, and that's before Forgejo, Woodpecker, Postgres, Portainer, MinIO, and the full observability stack (Prometheus, Grafana, Loki, Promtail, node-exporter, cadvisor) are even counted. An 8GB box will technically boot everything but leaves no headroom for a SonarQube scan and a Docker build running at the same time.

**Why 128GB disk, not the default 8–20GB many images ship with**: this was hit for real — the default root volume on a fresh Ubuntu AMI filled up mid-deployment (`no space left on device` failing every image pull) well before Harbor was even installed. Docker image layers across ~20 containers, Harbor's registry storage, Postgres data, and 30 days of Prometheus/Loki retention add up faster than the OS disk default assumes.

### Example: AWS EC2

```bash
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --instance-type m7i.xlarge \
  --key-name <your-key-pair> \
  --security-group-ids <your-sg-id> \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":128,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=forge-stack}]'
```

The `resolve:ssm:...` image ID always resolves to Canonical's own current 24.04 image — no marketplace tile to second-guess.

### Example: Azure

| Setting | Value |
|---|---|
| Image | Ubuntu Server 24.04 LTS - x64 Gen 2 (publisher: **Canonical** — several reseller-branded tiles show up in marketplace search; make sure it's this one) |
| Size | `Standard_D4s_v6` — 4 vCPU, 16 GiB RAM |
| OS disk | 128 GB, Premium SSD |
| Inbound ports | 22, 80, 443 |

```bash
az vm create \
  --resource-group <your-rg> \
  --name forge-stack-vm \
  --image Ubuntu2404 \
  --size Standard_D4s_v6 \
  --os-disk-size-gb 128 \
  --storage-sku Premium_LRS \
  --admin-username azureuser \
  --generate-ssh-keys
az vm open-port --resource-group <your-rg> --name forge-stack-vm --port 80,443
```

**Security group / firewall**: open **22** (SSH), **80**, and **443** inbound. Nothing else — Traefik is the only public entry point; every other service is reached through it, not exposed directly.

---

## 2. Install Docker

SSH into the instance, then:

```bash
curl -fsSL https://get.docker.com | sudo sh
```

If you're not already root (check with `whoami`), also run:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Confirm it worked:

```bash
docker --version
docker compose version
```

---

## 3. Clone the repo

```bash
git clone https://github.com/VarshithChand/Open-Source-Infra-Managemanet.git
cd Open-Source-Infra-Managemanet/deploy
```

---

## 4. DNS (skip this step entirely if testing locally with `DOMAIN=localhost`)

If deploying against a real domain, point these **A records** at the instance's public IP *before* continuing — Traefik requests a Let's Encrypt certificate for each on first boot, and repeated attempts against unresolved records burn toward Let's Encrypt's rate limit:

| Host | Purpose |
|---|---|
| `forgejo.<domain>` | Git hosting |
| `ci.<domain>` | Woodpecker CI |
| `sonar.<domain>` | SonarQube |
| `registry.<domain>` | Harbor |
| `ops.<domain>` | Portainer |
| `storage.<domain>` | MinIO API |
| `storage-console.<domain>` | MinIO console |
| `grafana.<domain>` | Grafana |
| `traefik.<domain>` | Traefik dashboard |
| `demo.<domain>` | Sample app (only if you deploy it later) |

Confirm propagation before moving on:

```bash
dig forgejo.<domain> +short
```

Should print the instance's IP. If it doesn't yet, wait — DNS propagation ranges from seconds (Cloudflare) to a couple hours depending on your provider.

---

## 5. Run the setup script

```bash
./setup.sh <your-domain>        # or: ./setup.sh localhost
```

This single command:

- Checks Docker, Compose, and `curl` are present
- Raises `vm.max_map_count` (required for SonarQube's embedded Elasticsearch — without this it crash-loops on startup)
- Generates every credential the stack needs — alphanumeric only, deliberately. Every password-escaping bug hit building this platform traced back to a literal `$` getting mangled by some layer of templating (Docker Compose's own variable interpolation, and separately, a distinct bug in Harbor's own config templating); scripted secrets simply don't use one, which sidesteps the entire class of bug rather than requiring you to get the escaping right by hand
- Brings up Traefik and Postgres, waits for Postgres to actually report healthy (not just started)
- Brings up Forgejo, SonarQube, Portainer, MinIO, the full observability stack, and the nightly backup job
- Waits for Forgejo to actually respond before finishing (a real `-f` HTTP-failure-aware check, not just "did the container start")

It'll print your generated Traefik dashboard password once — copy it immediately, and read `.env.CREDENTIALS.txt` for the rest before deleting it.

If you'd rather see and run each step by hand instead of trusting a script, the fully manual version — with the reasoning behind each step — is in [`deploy/README.md`](deploy/README.md).

---

## 6. The five steps no script can do for you

These are inherent to five tools' own first-run flows, not a gap in this repo — each needs exactly one pass through its own UI, once.

### 6.1 — Forgejo

Open the URL the script printed (`http(s)://forgejo.<domain>/`). Complete the install screen — the database connection is pre-filled from the environment, so you only need to set your admin account. **Use a username with no spaces** — it's a login credential, not a display name (a space in it will fail Forgejo's own validation on submit).

### 6.2 — Register Woodpecker as an OAuth app

In Forgejo: **Settings → Applications → Manage OAuth2 Applications → Create a new OAuth2 Application**

- Name: `Woodpecker CI`
- Redirect URI: `https://ci.<domain>/authorize` (or `http://` if `DOMAIN=localhost`) — **the scheme has to match exactly** what Woodpecker will actually be served over, or "Login via Forgejo" fails with a redirect URI mismatch

Copy the **Client ID** and **Client Secret** into `.env`:

```
WOODPECKER_FORGEJO_CLIENT=<client id>
WOODPECKER_FORGEJO_SECRET=<client secret>
```

Also add your Forgejo username to `WOODPECKER_ADMIN` in `.env` — without this, even your own first login fails with "cannot register \<user\>. registration closed" (`WOODPECKER_OPEN=false` closes self-registration entirely, including for the account meant to be the admin, unless it's explicitly listed here).

Then bring Woodpecker up:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d woodpecker-server woodpecker-agent
```

(Drop `-f docker-compose.tls.yml` if `DOMAIN=localhost`.)

Open `http(s)://ci.<domain>/` and sign in with **Login via Forgejo**.

### 6.3 — SonarQube

Open `http(s)://sonar.<domain>/`, log in with `admin` / `admin` (forced password change on first login), then **My Account → Security → Generate Token**. You'll use this token as a Woodpecker secret (`SONAR_TOKEN`) on any repo whose pipeline runs a quality-gate step — see [`demo-app/.woodpecker.yml`](demo-app/.woodpecker.yml) for a real, working example of that pipeline.

### 6.4 — Harbor

Not part of the base compose file — it ships its own installer that generates a multi-container stack from a `harbor.yml` config, and hand-rolling that into the main file would fight Harbor's own lifecycle tooling. Full steps, including three real gotchas hit running it (a robot-account naming assumption that didn't match reality, a bind-mounted database that `down -v` silently doesn't reset, and a `$`-in-password bug distinct from the one already avoided above): [`deploy/harbor/README.md`](deploy/harbor/README.md).

### 6.5 — Portainer

Open `http(s)://ops.<domain>/` and set the initial admin account. **Do this promptly** — Portainer's setup wizard self-locks a few minutes after the container starts for security; if you miss the window, restart the container to reopen it:

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml restart portainer
```

---

## 7. Connecting to everything — the access table

| Service | URL | First login |
|---|---|---|
| Forgejo | `http(s)://forgejo.<domain>/` | set during install |
| Woodpecker CI | `http(s)://ci.<domain>/` | via "Login with Forgejo" |
| SonarQube | `http(s)://sonar.<domain>/` | `admin` / `admin` (forced change) |
| Harbor | `http(s)://registry.<domain>/` | `admin` / your `harbor_admin_password` |
| Portainer | `http(s)://ops.<domain>/` | set on first visit |
| MinIO console | `http(s)://storage-console.<domain>/` | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` from `.env` |
| Grafana | `http(s)://grafana.<domain>/` | `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` from `.env` — **not** your personal Forgejo login, an easy mix-up |
| Traefik dashboard | `http(s)://traefik.<domain>/` | the credentials `setup.sh` printed |

### Verify it's actually working, not just running

```bash
docker compose -f docker-compose.yml -f docker-compose.tls.yml ps
```

Every service should show `Up` (several show `(healthy)` specifically — Postgres, cadvisor, node-exporter among them).

In Grafana, **Explore** → switch datasource to **Prometheus** → run `up` — every scrape target should show `1`. Switch to **Loki** → run `{compose_service=~".+"}` → real log lines should appear.

---

## 8. Prove the CI/CD path actually works

Push a trivial change to [`demo-app/`](demo-app/) (its canonical copy lives on your new Forgejo instance once you push it there) and watch it flow through Woodpecker: `test` → `code-quality` (SonarQube gate) → `build-and-push` (image lands in Harbor, Trivy-scanned). Full walkthrough, including why the `deploy` step is deliberately commented out (Portainer Community Edition has no stack webhooks — confirmed by hitting it directly, not assumed): [`demo-app/README.md`](demo-app/README.md).

---

## If something breaks

This exact path — a fresh VM, this exact sequence — surfaced real bugs while building it: DNS/TLS scheme mismatches, two distinct `$`-in-password bugs, a database reset that silently no-oped, naming assumptions that didn't hold, a CI platform's default security posture blocking a build step. Every one of them, and the actual fix, is written up in the [wiki's Real World Gotchas page](https://github.com/VarshithChand/Open-Source-Infra-Managemanet/wiki/Real-World-Gotchas) — check there before assuming a new failure is unprecedented.
