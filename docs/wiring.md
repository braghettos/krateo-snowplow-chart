# snowplow — composition wiring & operations (chart repo)

The `chart/values.yaml` surface, how the installer pins and wires snowplow, its dependencies, and
the real operational gotchas. Everything is traced to the chart; where a stale note disagrees with
the rendered chart, the chart wins.

## The `values.yaml` surface (`chart/values.yaml`)

### Exposure

- `service.type: LoadBalancer`, `service.port: 8081` (`values.yaml:50-52`). The Service maps
  `port` → `targetPort: http` (`service.yaml:10-13`); `nodePort` is only rendered when
  `service.type == NodePort` (`service.yaml:14-16`). Expose snowplow through the **installer CR**,
  not by hand-patching the Service.
- `ingress.enabled: false` by default (`values.yaml:61-62`); HPA off
  (`autoscaling.enabled: false`, `values.yaml:143-147`).

### The single http/8081 port + probes

The snowplow binary (1.0.x ship line) has **no dedicated probe listener** — it serves `/health`
and `/readyz` on the single `http` port (`PORT`, 8081), so **all three probes target `http`**
(`values.yaml:54-59,96-105`). Do not re-introduce `probePort`/`PROBE_PORT`: that split lived only on
the abandoned 0.25.x line and was never implemented on the ship line (`values.yaml:56-59`).

- `startupProbe` `GET /health`, `failureThreshold 36 × periodSeconds 10` ≈ 6 min headroom for image
  pull / scheduling (`values.yaml:111-117`).
- `livenessProbe` `GET /health`, widened to a ~50s window vs. the 30s k8s defaults
  (`values.yaml:123-129`).
- `readinessProbe` `GET /readyz`, `periodSeconds 5` — `/readyz` flips to 200 once informers complete
  their initial LIST/WATCH sync, **independent of the multi-minute L1 prewarm loop**; the pod goes
  Ready as soon as it can serve cold-L1 traffic, misses fall through to a foreground resolve
  (`values.yaml:131-141`). `progressDeadlineSeconds: 1200` is the cold-first-LIST safety net at 50K
  compositions (`values.yaml:18-22`).

### Resources & Go runtime (memory)

- `resources`: limits `cpu 4 / memory 8Gi`, requests `cpu 2 / memory 4Gi` (`values.yaml:88-94`),
  right-sized from 50K-composition × 1000-user stress data (peak heap ~3.9 GB, peak RSS ~6 GB,
  `values.yaml:72-87`).
- **`GOMEMLIMIT: 7GiB`** (`values.yaml:191`) — the load-bearing memory knob. It MUST sit **below**
  the container memory limit (8Gi) so the Go runtime backpressures via aggressive GC before Linux
  OOM-kills the pod. Setting `GOMEMLIMIT` ≥ the container limit is a misconfiguration that has
  caused OOM-kill incidents (`values.yaml:184-192`). `GOGC: "50"` trades ~1% CPU for tighter
  headroom (`values.yaml:192-193`). If you change `resources.limits.memory`, change `GOMEMLIMIT`
  with it (keep it ~1 GiB under the limit).

### Cache

- **`CACHE_ENABLED: "true"`** (`values.yaml:194`). The in-process MemCache replaced the old Redis
  sidecar (v0.25.266+), so `initContainers: []` (`values.yaml:170-171`). Setting
  `CACHE_ENABLED: "false"` is a **transparent fallback** to the direct apiserver — same data, same
  RBAC, just slower — not a degraded mode (see the code repo's
  [caching deep-dive](https://github.com/braghettos/krateo-snowplow/blob/main/docs/architecture/caching.md)).

### Config delivery (env, ConfigMap, envFrom)

- The container has **no direct `env:` array**. Every var goes under `.Values.env`, rendered into the
  chart's `<fullname>` ConfigMap and consumed via `envFrom` (`values.yaml:177-179`,
  `configmap.yaml:10-12`, `deployment.yaml:40-47`). The ConfigMap also hardcodes `PORT` (= 8081) and
  `AUTHN_NAMESPACE` (= the release namespace) (`configmap.yaml:8-9`).
- Defaults under `env`: `DEBUG: "false"`, `BLIZZARD: "false"`, `JQ_MODULES_PATH: /jq-modules`,
  `GOMEMLIMIT`, `GOGC`, `CACHE_ENABLED` (`values.yaml:180-194`).
- `jwtSignKeySecretName: jwt-sign-key` (`values.yaml:196`) — mounted as a Secret `envFrom`
  (`deployment.yaml:43-44`); the named Secret must exist in the namespace.
- **`extraEnvFrom`** appends extra `envFrom` sources without re-templating. The default picks up the
  externally-managed `snowplow-api-override` ConfigMap with **`optional: true`**
  (`values.yaml:165-168`) — owned by the portal/frontend blueprint, not this chart.

### Volumes

Only **one** volume is mounted: the chart's own `<fullname>-jq-custom-modules` ConfigMap, read-only
at `/jq-modules` (`deployment.yaml:70-80`). `volumes`/`volumeMounts` default to `[]`
(`values.yaml:158-160`). The Phase-1 prewarm walker reads the frontend nav-roots ConfigMap via the
**k8s API**, not via a mount (`values.yaml:153-157`).

## Dependencies (what must exist around snowplow)

- **The `snowplow-crd` Composition** (the `restactions.templates.krateo.io` CRD from
  `crds-subchart/`, version `0.21.1`) — deployed as its own Composition. The app chart deliberately
  does NOT bundle it (`chart/Chart.yaml:31-35`); see [overview.md](overview.md).
- **The `jwt-sign-key` Secret** in the release namespace (`envFrom` secretRef; the pod won't start
  without it).
- **Cluster RBAC for cluster-wide read** — the chart ships its own ClusterRole +
  ClusterRoleBinding granting `get/list/watch` on `*`/`*` plus `create` on the
  access-review APIs (`clusterrole.yaml:21-38`); needed because snowplow discovers CRDs at runtime
  and starts informers on them.
- **Optional, external:** the `snowplow-api-override` ConfigMap (owned by the portal blueprint),
  picked up only if present.

## How the installer wires it

The [krateo-installer](https://github.com/braghettos/krateo-installer) umbrella owns snowplow's
`CompositionDefinition` (this repo ships none for the app itself, `README.md:24-29`). The umbrella
pins `spec.chart.version` to the released chart tag and points `core-provider` at
`oci://ghcr.io/braghettos/krateo/snowplow`; `core-provider` reads `chart/values.schema.json`,
generates the typed CRD, and reconciles one Composition per instance. The deployed chart version is
readable from `CompositionDefinition.spec.chart.version` (the tag at which to fetch THIS repo's docs).
The `crds-subchart` is pinned separately by the installer.

## Gotchas

- **`GOMEMLIMIT` must stay below the container memory limit.** ≥ the limit and the Go runtime never
  sees pressure → OOM-kills. Always keep ~1 GiB headroom (`values.yaml:184-192`).
- **`jwt-sign-key` Secret is required.** It is a non-optional `envFrom` secretRef
  (`deployment.yaml:43-44`); if absent the pod stalls in `ContainerCreating` /
  `CreateContainerConfigError` on the missing Secret.
- **`snowplow-api-override` is optional.** It is mounted `optional: true`
  (`values.yaml:165-168`), so a missing override ConfigMap does NOT block the pod.
  > **Stale-note correction.** Older agent prose claims "the snowplow chart mounts a
  > `snowplow-cache-warmup` ConfigMap non-optionally — if missing the pod stalls ContainerCreating
  > on FailedMount." **That is NOT true of this chart.** The Deployment mounts exactly one volume:
  > the `<fullname>-jq-custom-modules` ConfigMap (`deployment.yaml:70-80`); there is no
  > `snowplow-cache-warmup` volume or mount anywhere in `chart/templates/`. The only external
  > config source is `snowplow-api-override`, and it is `optional`. Treat the chart as authoritative.
- **`SNOWPLOW_API_BASE_URL` is a *frontend*-side setting, not in this chart.** The frontend's
  `config.json` carries `SNOWPLOW_API_BASE_URL` pointing at this Service — if snowplow is down or
  that URL doesn't resolve, the portal renders "404 / widget does not exist" even after a successful
  login. That value is owned by the frontend blueprint; it is not part of `chart/values.yaml`. (Note
  the `extraEnvFrom` `snowplow-api-override` ConfigMap is the *server*-side override and is unrelated
  to the frontend's base URL.)
- **Probes never target a second port.** The binary serves health on 8081 only; re-adding a
  `PROBE_PORT` split will break readiness on the ship line (`values.yaml:54-59`).
- **Don't bundle the CRD.** Adding `crds-subchart` as a dependency of `chart/` collides with the
  `snowplow-crd` release ("cannot be imported into the current release", `chart/Chart.yaml:31-35`).

## See also

- [overview.md](overview.md) — chart layout, CompositionDefinition, what gets deployed.
- [crds.md](crds.md) — the RESTAction CRD fields.
- Code repo runtime view: `braghettos/krateo-snowplow`
  [`ARCHITECTURE.md`](https://github.com/braghettos/krateo-snowplow/blob/main/ARCHITECTURE.md),
  [`docs/architecture/`](https://github.com/braghettos/krateo-snowplow/tree/main/docs/architecture)
  (caching, prewarm, RBAC/UAF, request lifecycle).
