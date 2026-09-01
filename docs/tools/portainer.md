# Portainer — Deployment & Container Management

## What it is

Portainer is a web UI for managing Docker (and optionally Kubernetes/Swarm) environments — containers, stacks, images, volumes, networks — without needing to SSH into the host for routine operations.

## Role in this platform

Portainer is the runtime control plane. It's the last stop in the CI/CD path: once Harbor has a scanned, tagged image, a webhook call to Portainer redeploys the relevant stack with the new image. It's also the day-to-day operational tool — checking container health, tailing logs, restarting a stuck service, or inspecting resource usage without needing full shell access to the host.

## Key features used

- **Stack redeploy webhooks** — each stack has a unique webhook URL; calling it pulls the latest image and recreates the container, which is exactly the hook Woodpecker/Harbor calls on a successful build
- **Stacks (Compose-in-the-UI)** — application stacks are defined as compose files, editable and redeployable from the UI or via Git integration
- **RBAC** — team members get scoped access (e.g., restart/view only) without full Docker socket access
- **Environment overview** — CPU/memory/container count at a glance, useful as a first stop before diving into Grafana for historical data

## Why Portainer

Portainer isn't replacing a SaaS product so much as replacing "SSH in and run `docker compose up -d`" with something auditable, permissioned, and usable by teammates who shouldn't have raw host access.

## Operational notes

- Requires access to the Docker socket (`/var/run/docker.sock`) — the one deliberate exception to "nothing internal-only touches the edge," since Portainer's own dashboard still needs to be reachable
- Sits behind Traefik at `ops.example.com`, with basic auth as a second layer given the privilege level this UI carries
