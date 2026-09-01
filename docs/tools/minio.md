# MinIO — Object Storage

## What it is

MinIO is a high-performance, S3-API-compatible object storage server. Anything written with the AWS S3 SDK/CLI works against MinIO unmodified — it's a drop-in for S3 that runs on your own infrastructure.

## Role in this platform

MinIO is the platform's blob storage and backup target:

- Nightly database dumps from Forgejo, Harbor, SonarQube, and Grafana are pushed here as the backup path
- Build artifacts from Woodpecker pipelines (test reports, coverage output, build logs) that don't belong in the registry are stored here
- Any deployed application that needs object storage (uploaded files, generated reports) points at MinIO instead of AWS S3

## Key features used

- **S3 API compatibility** — existing S3 tooling (`mc` CLI, `boto3`, `aws-sdk`) works without modification, just a different endpoint
- **Bucket versioning** — enabled on the backup bucket specifically, so a bad nightly dump doesn't overwrite the last-known-good one
- **Bucket policies / access keys per service** — each service that writes to MinIO gets its own scoped access key rather than a shared credential
- **Lifecycle rules** — old build artifacts expire automatically after a retention window (e.g. 30 days) to keep storage bounded

## Why MinIO over the alternatives

| Option | Trade-off |
|---|---|
| AWS S3 | Recurring cost, data leaves self-hosted infrastructure, defeats the point of the project |
| A shared Docker volume | No API, no versioning, no access control between services |
| NFS | Works for file storage but doesn't give the S3 API that most backup/artifact tooling already expects |

## Operational notes

- Runs in single-node mode for this scale; MinIO also supports distributed/erasure-coded mode if the project ever needed multi-node durability
- Console (port 9001) sits behind Traefik at `storage.example.com`; the S3 API port stays internal-only where possible, reachable directly by other containers on the `internal` network
