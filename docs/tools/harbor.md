# Harbor — Container Registry

## What it is

Harbor is a CNCF-graduated container registry that goes beyond a bare OCI registry: it adds role-based access control, image vulnerability scanning, image signing, replication between registries, and a retention/garbage-collection policy engine.

## Role in this platform

Harbor is where every built image lands and where deployable images are gated. Woodpecker pushes images here after a successful build; Harbor scans each image for known CVEs before it's allowed to be pulled by Portainer for deployment. Nothing reaches the runtime layer without passing through this scan.

## Key features used

- **Project-based RBAC** — each team/repo gets its own project namespace with its own push/pull permissions
- **Vulnerability scanning (Trivy)** — every pushed image is scanned automatically; the deploy step checks scan status before triggering Portainer
- **Tag retention policy** — old, untagged, or superseded images are garbage-collected on a schedule so registry storage doesn't grow unbounded
- **Webhooks** — Harbor can notify Portainer directly on a successful push, as an alternative to Woodpecker calling the deploy hook itself

## Why Harbor over the alternatives

| Option | Trade-off |
|---|---|
| Docker Hub | Rate limits on pulls; private repos are a paid tier; no self-hosted option |
| Bare `registry:2` | No scanning, no RBAC, no UI — just blob storage with an API |
| AWS ECR / GCR | Ties the platform to a specific cloud provider, defeating the self-hosted goal |

## Operational notes

- Deployed via Harbor's own installer (`install.sh` against `harbor.yml`), which brings up its internal Postgres, Redis, and job service — then the front-end container joins the shared `edge` network for Traefik routing
- Backed by its own Postgres instance, included in the nightly backup to MinIO
- Sits behind Traefik at `registry.example.com`
