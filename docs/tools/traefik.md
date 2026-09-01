# Traefik — Reverse Proxy & Edge Router

## What it is

Traefik is a reverse proxy and load balancer designed around dynamic service discovery — it watches the Docker API directly and builds its routing table from container labels, instead of needing a static config file edited every time a service changes.

## Role in this platform

Traefik is the single entry point for every web-facing service in the stack. Nothing is exposed directly on its own port; every service joins the shared `edge` Docker network and gets two or three labels, and Traefik does the rest — routing, TLS, and (where needed) auth middleware.

## Key features used

- **Docker provider** — routing rules live as labels on each service's own compose definition, so adding a new service to the platform means adding labels, not touching a central proxy config
- **Automatic TLS via ACME/Let's Encrypt** — every subdomain gets a valid certificate issued and renewed automatically, no manual certbot cron job
- **Middleware chains** — HTTP→HTTPS redirect globally; basic auth stacked in front of high-privilege UIs like Portainer as a second layer beyond the app's own login
- **Dashboard** — Traefik's own routing dashboard (itself behind auth) is useful for confirming a new service registered correctly before debugging further

## Why Traefik over the alternatives

| Option | Trade-off |
|---|---|
| NGINX + Certbot | Works, but every new service means manually editing an NGINX config and reloading — no auto-discovery |
| An external load balancer (cloud ALB) | Cloud-provider specific, and this project deliberately keeps everything on infrastructure you control |
| Caddy | Also has automatic TLS and is simpler for static routing, but Traefik's Docker-label-driven discovery fits a compose-heavy, frequently-changing service set better |

## Operational notes

- Requires read access to the Docker socket to watch for container start/stop events — the other deliberate exception (alongside Portainer) to keeping internal-only services off anything touching the socket
- Own metrics endpoint scraped by Prometheus, with an official Grafana dashboard for request rate, latency, and error rate per router
