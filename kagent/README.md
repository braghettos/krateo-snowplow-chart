# `krateo-snowplow-agent` — the snowplow component specialist

A [kagent](https://kagent.dev) Agent that generates valid Krateo **RESTAction** CRDs (JQ filters,
endpoint refs) and is the **dedicated expert on RESTActions**. Per the
[`/kagent` standard](https://github.com/braghettos/krateo-autopilot/blob/main/AGENTS-VERSIONING.md)
it knows its component from this chart's `Chart.yaml` `sources`:

- **codebase:** `github.com/braghettos/snowplow` (the service that executes RESTActions)
- **chart that packages it:** `github.com/braghettos/krateo-snowplow-chart` (`crds-subchart/` holds the
  `RESTAction` CRD)

It reads both via github MCP tools to ground answers in the real CRD schema + source. Reachable only
through the `krateo-autopilot` orchestrator (registered via `extraAgents`).

Published to `oci://ghcr.io/braghettos/krateo/krateo-snowplow-agent` (pinned `0.1.0`). Shipped as
an installer component gated on `features.observabilityAgents`.
