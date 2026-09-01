# Loki + Promtail — Log Aggregation

## What they are

**Loki** is Grafana Labs' log aggregation system, built to be as cheap and simple to operate as Prometheus — instead of indexing full log text (like Elasticsearch), it indexes only metadata labels and stores the raw log content compressed, which is what keeps it lightweight on a single-host deployment. **Promtail** is the agent that tails container logs and ships them to Loki with the right labels attached.

## Role in this platform

Every container's stdout/stderr is picked up by Promtail and shipped to Loki, labeled by container name, stack, and service — the same label model Prometheus uses for metrics. That symmetry is what makes the Grafana pairing work: a metrics panel and its corresponding logs use the same labels, so pivoting from "CPU spiked" to "here's what the container logged during that spike" is one click.

## Key features used

- **Docker service discovery** — Promtail auto-discovers containers via the Docker socket and labels each log stream with the container's name/compose project, no manual log-path configuration per service
- **LogQL** — Loki's query language, close enough to PromQL that switching between metrics and log queries in Grafana doesn't require learning a second mental model
- **Label-based retention** — logs from noisy/low-value sources (health-check pings) can be dropped or given a shorter retention than pipeline and application logs

## Why Loki over the alternatives

| Option | Trade-off |
|---|---|
| ELK / OpenSearch | Full-text indexing is powerful but resource-heavy — overkill for a single-host platform, and a second, unrelated query language to maintain |
| Cloud logging (CloudWatch Logs, Datadog Logs) | Per-GB ingestion pricing, and again ties the platform to a vendor |
| `docker logs` / raw files | No search, no retention policy, no correlation with metrics |

## Operational notes

- Both stay on the `internal` network; only Grafana (which queries Loki) needs a path to it
- Promtail runs with read-only access to `/var/lib/docker/containers` and the Docker socket — no write access needed

## A note on Promtail's status

Promtail reached end-of-life in March 2026 — Grafana Labs stopped shipping updates and now points new deployments at **Grafana Alloy**, its unified telemetry collector, instead. This stack still runs Promtail (pinned to its last release, `3.6.11`, in `deploy/docker-compose.yml`) because it's the piece this project set out to demonstrate and it continues to function correctly. Migrating to Alloy — a config-format change, not an architecture change, since Loki stays the log store either way — is the natural next step for anyone taking this stack past a reference deployment.

