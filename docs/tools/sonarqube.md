# SonarQube — Static Analysis & Code Quality

## What it is

SonarQube is a static analysis platform that scans source code for bugs, code smells, security vulnerabilities, and duplicated logic, then scores the result against a configurable **quality gate** — a pass/fail threshold a build has to clear.

## Role in this platform

SonarQube is the quality checkpoint inside the Woodpecker pipeline, positioned between "tests passed" and "build the image." A pipeline can have green tests and still fail here — e.g., if test coverage on new code drops below the threshold, or the scan finds a new security hotspot. That failure blocks the pipeline before an image is ever built, which is deliberate: quality issues are cheaper to catch before an image exists than after it's already in the registry.

## Key features used

- **Quality gates** — the default "Sonar way" gate (coverage on new code, duplication, maintainability rating) enforced per project, failing the Woodpecker step on violation
- **Pull request decoration** — scan results and new issues are reported back as PR comments/status checks on Forgejo, visible in review before merge
- **Security hotspot detection** — flags patterns like hardcoded secrets, SQL string concatenation, or insecure deserialization for manual review, distinct from the auto-failing bugs/vulnerabilities category
- **Multi-language analyzers** — one SonarQube instance covers every language used across the platform's repos rather than needing a per-language linter setup

## Why SonarQube over the alternatives

| Option | Trade-off |
|---|---|
| SonarCloud | SaaS-only, and free tier is public-repos-only — doesn't fit a private, self-hosted platform |
| Per-language linters only (ESLint, Pylint, etc.) | Catch style issues, not the security/duplication/maintainability analysis SonarQube specializes in; still worth running alongside, not instead of |
| CodeClimate | Primarily SaaS; self-hosted option is less actively maintained |

## Operational notes

- Community Edition is sufficient for this platform's scale; branch analysis and some governance features are Enterprise-only and intentionally out of scope
- Backed by its own Postgres instance, included in the nightly backup to MinIO
- Sits behind Traefik at `sonar.example.com`
