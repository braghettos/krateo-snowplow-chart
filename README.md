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
| `crds-subchart/` | `snowplow-crd` | `oci://ghcr.io/braghettos/krateo/snowplow-crd` | independent `0.21.x` (currently `0.21.3`; not the app tag) |

The `restactions` CRD versions independently of the snowplow app, so `crds-subchart/Chart.yaml`
carries a literal `version` (currently `0.21.3`) rather than the `CHART_VERSION` placeholder — the
release workflow leaves it untouched and only bumps it when the CRD schema actually changes.

## Compatibility matrix

A release tag (`X.Y.Z`) packages **both** charts at once, but they are **versioned
independently**:

- **`snowplow`** (app) — chart version = the release tag; `appVersion` = the bundled snowplow image.
- **`snowplow-crd`** (CRD) — its own literal `0.21.x` version, bumped **only** when the
  `restactions` CRD schema changes (it is *not* the release tag).

| Release tag | `snowplow` chart → image (`appVersion`) | `snowplow-crd` | CRD synced from | Highlights |
|---|---|---|---|---|
| `1.0.28` | snowplow `1.5.2` | `0.21.3` | snowplow `1.4.1` | Reverted the customer-resolve memory cap (the OOM fix is the apistage fold, on by default). |
| `1.0.27` | `1.5.1` | `0.21.3` | `1.4.1` | Process-wide resolve memory cap — **superseded; use `1.0.28`**. |
| `1.0.26` | `1.5.0` | `0.21.3` | `1.4.1` | `GET /rbac` inspect endpoint; `RESOLVED_CACHE_APISTAGE_ENABLED` folded under `CACHE_ENABLED`. |
| `1.0.25` | `1.4.3` | `0.21.3` | `1.4.1` | Chart-only: configmap-checksum pod-template annotation (config changes roll pods). |
| `1.0.24` | `1.4.3` | `0.21.3` | `1.4.1` | x509 fix: CA-bearing SA transport for bare group-discovery (`/apis/<g>/<v>`) api-steps. |
| `1.0.23` | `1.4.2` | `0.21.3` | `1.4.1` | Discovery-storm fix (per-group dedup + memoised discovery). |
| `1.0.22` | `1.4.0` / `1.4.1` | `0.21.3` | `1.4.1` | 1.4.x entry: in-process resolve + external-no-cache + `/call`-loopback retirement (`spec.api[].resolve`, default `true`). `1.4.1` = CRD keep-policy hotfix. |

### CRD compatibility

- **`snowplow-crd 0.21.3`** (synced from snowplow `1.4.1`) is the CRD for the **entire `1.4.x` →
  `1.5.x` app line.** The `restactions` `v1` schema — `spec.api[]` (`path`, `verb`, `endpointRef`,
  `dependsOn`, `continueOnError`, `userAccessFilter`), `spec.api[].resolve` (added with the 1.4.0
  unified resolve), and `spec.filter` — has **not changed since `1.4.1`**; the `1.5.x` app releases
  did not touch the CRD (their CRD-sync PRs were no-ops).
- Earlier CRD syncs: `0.21.x` from snowplow `1.1.0` (#21) and `1.0.3` (#15) — for app versions
  before `1.4.x`.
- `restactions.templates.krateo.io` is served + storage version **`v1`** (single version) and
  carries `helm.sh/resource-policy: keep`, so it survives `helm uninstall`.

Install **both** charts (the installer umbrella deploys each as its own Composition): `snowplow`
at the release tag and `snowplow-crd` at `0.21.3`.

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

Push a semver tag (`X.Y.Z`) — CI packages `chart/` and `crds-subchart/` and publishes both to
`oci://ghcr.io/braghettos/krateo`.

## Links

- Installer umbrella: https://github.com/braghettos/krateo-installer
- Upstream: https://github.com/krateoplatformops/snowplow
