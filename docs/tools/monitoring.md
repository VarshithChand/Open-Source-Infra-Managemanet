# Prometheus + Grafana — Metrics & Dashboards

## What they are

**Prometheus** is a time-series database and scraping engine — it pulls metrics from targets on a schedule and stores them queryable by label via PromQL. **Grafana** is the visualization layer on top: dashboards, alerting, and a query editor that speaks Prometheus's (and Loki's) query languages natively.

## Role in this platform

Every container in the stack exposes or is scraped for metrics; Prometheus is the single collection point, and Grafana is the single pane of glass for both metrics and (via the Loki data source) logs — one dashboard, two data sources, no context-switching between tools.

## Key features used

- **`cadvisor` + `node-exporter` targets** — container-level (CPU, memory, network per container) and host-level (disk, load, filesystem) metrics without instrumenting every app individually
- **Scrape configs per service** — Harbor, Forgejo, Traefik, and Woodpecker all expose Prometheus-compatible `/metrics` endpoints, scraped directly
- **Alertmanager rules** — e.g., disk usage above 85%, a container restarting more than N times in an hour, or Harbor's scan queue backing up
- **Grafana dashboards** — pre-built dashboards per service (Traefik's official dashboard, a container-overview dashboard from `cadvisor` metrics, a custom "pipeline health" dashboard built from Woodpecker's metrics)
- **Grafana + Loki data source** — clicking a spike on a metrics panel can jump straight to the logs for that time window and container

## Why Prometheus/Grafana over the alternatives

| Option | Trade-off |
|---|---|
| Datadog / New Relic | Per-host/per-metric SaaS pricing; data leaves your infrastructure |
| CloudWatch | Cloud-provider specific, doesn't fit a self-hosted, provider-agnostic stack |
| InfluxDB + Chronograf | Smaller ecosystem of pre-built dashboards/exporters compared to Prometheus |

## Operational notes

- Prometheus stays on the `internal` network — nothing needs to hit it directly except Grafana
- Grafana sits behind Traefik at `grafana.example.com`
- Retention is capped (e.g. 15–30 days) to keep Prometheus's local TSDB size manageable on a single host; longer retention would mean adding Thanos or Mimir, deliberately out of scope for this project's scale
