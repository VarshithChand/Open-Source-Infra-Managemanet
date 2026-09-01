# Woodpecker CI — Pipeline Runner

## What it is

Woodpecker is a lightweight, container-native CI/CD engine — a community-maintained fork of Drone. Pipelines are defined as YAML (`.woodpecker.yml`) in the repo itself, and every step runs as its own container.

## Role in this platform

Woodpecker is the automation backbone: it's the thing that turns "code was pushed" into "tested, scanned, built, and deployed." It sits between Forgejo (trigger) and Harbor/Portainer (targets).

A typical pipeline run:

1. Triggered by a Forgejo webhook on push/PR
2. Installs dependencies, runs the test suite
3. Runs a SonarQube scan and fails the build if the quality gate isn't met
4. Builds the container image
5. Pushes it to Harbor (only on `main`)
6. Calls a Portainer webhook to redeploy

## Key features used

- **YAML pipelines checked into the repo** — the pipeline is versioned alongside the code it builds, no separate CI config UI to keep in sync
- **Secrets** — registry credentials, SonarQube tokens, and the Portainer webhook URL are stored as Woodpecker secrets, never in the repo
- **Step-level containers** — each pipeline step (test, scan, build, deploy) runs in its own isolated container image, so the pipeline environment is fully reproducible
- **Branch/event filters** — deploy steps run only on `main`; PRs run test + scan only

## Why Woodpecker over the alternatives

| Option | Trade-off |
|---|---|
| Jenkins | Far heavier to operate; plugin ecosystem is powerful but adds a lot of maintenance surface for a small platform |
| GitHub Actions | Requires GitHub; not usable against a self-hosted Forgejo instance |
| Drone | Woodpecker is Drone's community fork after Drone's license changed to a commercial model |

## Operational notes

- Runs as `woodpecker-server` (API/UI) + `woodpecker-agent` (executes pipeline steps); agents scale horizontally if pipeline volume grows
- Authenticates against Forgejo via OAuth2 — no separate user database
- Sits behind Traefik at `ci.example.com`
