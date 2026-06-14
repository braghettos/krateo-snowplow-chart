# krateo-snowplow-chart

Krateo PlatformOps **Snowplow** blueprint — a fork of
[`krateoplatformops/snowplow`](https://github.com/krateoplatformops/snowplow) packaged as a
Krateo blueprint: the upstream Helm chart plus a `values.schema.json` (so `core-provider` can
generate a typed CRD).

Snowplow is the portal **content/composition API**: the frontend SPA calls it
(`/call?resource=navmenus|routes|pages|panels|...`) to fetch every widget, navmenu and route.
A reachable Snowplow is a hard prerequisite for a working portal, not just analytics.

Part of the [krateo-installer](https://github.com/braghettos/krateo-installer) ecosystem.

## What it ships

| Path | Chart | OCI artifact | Versioning |
|------|-------|--------------|-----------|
| `chart/` | `snowplow` | `oci://ghcr.io/braghettos/krateo/snowplow` | tracks the git tag |
| `crd-chart/` | `snowplow-crd` | `oci://ghcr.io/braghettos/krateo/snowplow-crd` | pinned `0.21.0` (independent of the app tag) |

The `restactions` CRD versions independently of the snowplow app, so `crd-chart/Chart.yaml`
carries a literal `version: 0.21.0` rather than the `CHART_VERSION` placeholder — the release
workflow leaves it untouched.

## How the installer consumes it

The installer umbrella emits the `CompositionDefinition` for `snowplow`, pointing
`core-provider` at `oci://ghcr.io/braghettos/krateo/snowplow`; `core-provider` then generates the
typed CRD and reconciles one Composition per instance. This repo ships no standalone
`compositiondefinition.yaml` — the umbrella owns it.

## Local validation

```sh
helm lint chart
helm template smoke chart
```

## Release

Push a semver tag (`X.Y.Z`) — CI packages `chart/` and `crd-chart/` and publishes both to
`oci://ghcr.io/braghettos/krateo`.

## Links

- Installer umbrella: https://github.com/braghettos/krateo-installer
- Upstream: https://github.com/krateoplatformops/snowplow
