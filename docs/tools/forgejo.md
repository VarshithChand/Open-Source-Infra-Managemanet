# Forgejo — Git Hosting

## What it is

Forgejo is a self-hosted, lightweight Git forge — a community-governed fork of Gitea. It provides repository hosting, pull requests, issue tracking, wikis, and webhooks, i.e. the same core experience as GitHub, running entirely on infrastructure you control.

## Role in this platform

Forgejo is the source of truth. Every pipeline in the platform starts here: a push or merged PR fires a webhook that triggers Woodpecker CI. It's also where code review happens (PRs), where issues are tracked, and where OAuth applications are registered so other services (Woodpecker) can authenticate against it.

## Key features used

- **Repositories & branch protection** — `main` requires passing CI and at least one review before merge
- **Webhooks** — push/PR events notify Woodpecker
- **OAuth2 provider** — Woodpecker authenticates users via "Sign in with Forgejo" rather than a separate credential store
- **Actions/webhook secrets** — repo-level secrets for pipeline tokens

## Why Forgejo over the alternatives

| Option | Trade-off |
|---|---|
| GitHub | Not self-hostable on your own infra; free tier limits on private CI minutes |
| GitLab CE | Heavier resource footprint; bundles its own CI (redundant with Woodpecker here) |
| Gitea | Forgejo is Gitea's community/non-profit fork — same lightweight footprint, governance not tied to a single company |

## Operational notes

- Runs on SQLite for small deployments or Postgres for anything with concurrent write load
- Backed up nightly to MinIO alongside its Postgres dump
- Sits behind Traefik at `git.example.com`, TLS terminated at the edge
