# snowplow — deployment overview (chart repo)

What snowplow is, and **how it deploys** as a Krateo composition. This is the deployment view; the
internals/runtime view lives in the code repo `braghettos/krateo-snowplow`
([`ARCHITECTURE.md`](https://github.com/braghettos/krateo-snowplow/blob/main/ARCHITECTURE.md),
`docs/`). Every claim below is traced to a file in this repo — if a comment disagrees with what the
chart actually renders, the rendered chart wins.

## What snowplow is

The portal **content / composition API**. The Krateo frontend SPA calls it over `/call` to fetch
every navmenu, route, page, panel and widget definition+data; it composes that content on demand
from Kubernetes CRs (it is not a BFF and holds no product state). It also implements the
**`RESTAction`** CRD — declarative, JQ-shaped REST calls — which this repo ships (see
[crds.md](crds.md)). A reachable snowplow is a hard prerequisite for a working portal, not just
analytics.

This repo is the **braghettos fork packaged as a Krateo blueprint**: the Helm chart plus a
`values.schema.json` so `core-provider` can generate a typed CompositionDefinition CRD
(`README.md:3`).

## Repo layout — three charts

| Path | Chart name | OCI artifact | Versioning |
|------|------------|--------------|------------|
| `chart/` | `krateo-snowplow` | `oci://ghcr.io/braghettos/krateo/snowplow` | tracks the git tag (`Chart.yaml` `version: CHART_VERSION`, `chart/Chart.yaml:19`) |
| `crds-subchart/` | `krateo-snowplow-crd` | `oci://ghcr.io/braghettos/krateo/snowplow-crd` | pinned `0.21.1`, independent of the app tag (`crds-subchart/Chart.yaml:20`) |
| `kagent/chart/` | `krateo-snowplow-agent` | `oci://ghcr.io/braghettos/krateo/krateo-snowplow-agent` | `0.1.x`, independent (`kagent/chart/Chart.yaml`) |

The three version **independently**:

- **The main app chart** (`chart/`) is the deployable snowplow workload. `version` is the
  `CHART_VERSION` placeholder, substituted to the git tag at release; `appVersion` is the
  `APP_VERSION` placeholder, stamped from the latest semver tag of the code repo
  (`chart/Chart.yaml:19,23`). So the chart always deploys the container image the app actually
  published (`chart/values.yaml:24-32`).
- **The CRD subchart** (`crds-subchart/`) is deliberately **NOT bundled** into the app chart. Per
  the golden rule, CRDs live in a dedicated chart deployed as its own Composition (`snowplow-crd`);
  bundling makes the app release try to own the CRDs and collide with the `snowplow-crd` release
  ("cannot be imported into the current release") — see the note at `chart/Chart.yaml:31-35`. The
  CRD versions independently of the app (a literal `version: 0.21.1`, NOT the placeholder), so the
  release workflow leaves it untouched (`crds-subchart/Chart.yaml:14-20`).
  > **Chart vs. README:** the `README.md` table still says the CRD subchart is pinned `0.21.0`;
  > the actual `crds-subchart/Chart.yaml:20` is `0.21.1` (a minor additive schema refresh adding
  > `userAccessFilter.resourcesFrom` + the resource/resourcesFrom XOR rule). The chart wins.
- **The agent chart** (`kagent/chart/`) is the federated specialist agent (`krateo-snowplow-agent`)
  registered on `krateo-autopilot`; it versions on its own `0.1.x` line and is **not** the snowplow
  workload. `kagent/compositiondefinition.yaml` ships its CompositionDefinition (pinned `0.1.0`).

## The CompositionDefinition

There is **no standalone `compositiondefinition.yaml` for snowplow itself** in this repo — the
[krateo-installer](https://github.com/braghettos/krateo-installer) umbrella owns it
(`README.md:24-29`). The umbrella emits a `CompositionDefinition` pointing `core-provider` at
`oci://ghcr.io/braghettos/krateo/snowplow`; `core-provider` reads the chart's `values.schema.json`,
generates the typed CRD, and reconciles one Composition per instance. The deployed chart version is
cluster-observable from `CompositionDefinition.spec.chart.version` (this is the tag at which an agent
should fetch THIS repo's docs — see [llms.txt](llms.txt)).

The one CompositionDefinition that *does* live here is for the agent
(`kagent/compositiondefinition.yaml`): `core.krateo.io/v1alpha1`, name `krateo-snowplow-agent`,
namespace `krateo-system`, `spec.chart.version: "0.1.0"`.

## What the app chart deploys (`chart/templates/`)

Rendering the main `chart/` produces:

- **Deployment** (`deployment.yaml`) — one replica by default (`values.yaml:16`), the snowplow
  container exposing a **single `http` port (containerPort = `service.port` = 8081**,
  `deployment.yaml:56-59`, `values.yaml:52`). Config is delivered entirely via `envFrom`
  (`deployment.yaml:40-47`): the chart-managed ConfigMap, the `jwt-sign-key` Secret, and any
  `extraEnvFrom` entries. The container has **no direct `env:` array** — every env var is set
  through the ConfigMap (`values.yaml:177-179`). `progressDeadlineSeconds` defaults to 1200s as a
  cold-start safety net (`values.yaml:18-22`).
- **Probes** — all three target the single `http` port; the binary has no dedicated probe listener
  on the 1.0.x ship line (`values.yaml:54-59,96-105`):
  - `startupProbe` → `GET /health`, up to 6 min (`failureThreshold 36 × periodSeconds 10`,
    `values.yaml:111-117`).
  - `livenessProbe` → `GET /health` (`values.yaml:123-129`).
  - `readinessProbe` → `GET /readyz`, which flips to 200 once informers finish their initial
    LIST/WATCH sync — independent of the multi-minute L1 prewarm loop (`values.yaml:131-141`).
- **Service** (`service.yaml`) — type `LoadBalancer` by default, port 8081 → `targetPort: http`
  (`service.yaml:8-13`, `values.yaml:50-52`).
- **ConfigMaps** — two:
  - `<fullname>` (`configmap.yaml`) — the env ConfigMap: hardcodes `PORT` and `AUTHN_NAMESPACE`
    (the release namespace) and renders every key under `.Values.env`
    (`configmap.yaml:8-12`).
  - `<fullname>-jq-custom-modules` (`configmap.jq-custom-modules.yaml`) — the JQ custom modules
    from `chart/assets/custom-modules.jq`, mounted read-only at `/jq-modules`
    (`deployment.yaml:70-80`, `values.yaml:183` `JQ_MODULES_PATH: /jq-modules`).
- **RBAC** — `ServiceAccount` (`serviceaccount.yaml`), a `ClusterRole` granting **cluster-wide
  read** (`get/list/watch` on `*`/`*`) plus `create` on
  `selfsubjectaccessreviews`/`subjectaccessreviews`, and a `ClusterRoleBinding`
  (`clusterrole.yaml:21-38`, `clusterrolebinding.yaml`). The broad read is required because
  snowplow dynamically discovers CRDs at runtime and starts informers on newly-observed CR types
  (`clusterrole.yaml:8-20`).
- **Endpoint Secret** — `<fullname>-endpoint` (`endpoint.yaml`), an in-cluster `server-url`
  pointing back at the snowplow Service (`http://<fullname>.<ns>.svc:8081`, `insecure: "true"`) so
  RESTActions can call snowplow itself.
- **Optional** — `Ingress` (`ingress.yaml`, disabled by default, `values.yaml:61-62`) and an HPA
  (`hpa.yaml`, `autoscaling.enabled: false`, `values.yaml:143-147`).

For the full `values.yaml` surface (resources, `GOMEMLIMIT`, `CACHE_ENABLED`, exposure, the
`extraEnvFrom` override) and the operational gotchas, see [wiring.md](wiring.md). For the
RESTAction CRD fields, see [crds.md](crds.md).

## Cross-references

- **Code repo (internals & runtime):** `braghettos/krateo-snowplow` —
  [`ARCHITECTURE.md`](https://github.com/braghettos/krateo-snowplow/blob/main/ARCHITECTURE.md) and
  [`docs/llms.txt`](https://github.com/braghettos/krateo-snowplow/blob/main/docs/llms.txt). That set
  is versioned at the **image** tag (= chart `appVersion`); this set is versioned at the **chart**
  tag.
- **Installer umbrella:** `braghettos/krateo-installer` (owns snowplow's CompositionDefinition).
- **Upstream:** `krateoplatformops/snowplow`.
