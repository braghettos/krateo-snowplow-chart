#!/bin/bash
# sync-crds.sh — Stage 2 of the CRD pipeline: copy the canonical CRD
# manifests from the braghettos/snowplow repo's crds/ into this chart's
# crd-chart/templates/.
#
# WHY THIS EXISTS: the snowplow Go types (apis/templates/v1) generate
# crds/ in the snowplow repo; the deployed CRD ships from THIS repo's
# crd-chart. That hop was manual and silently drifted — a userAccessFilter
# field generated at Tag 0.30.9 never reached the deployed chart, so the
# apiserver pruned it off every RESTAction write (Ship 0.30.111 inert-UAF
# incident). This script makes the hop reproducible.
#
# LOCKSTEP VERSIONING CONVENTION (binding): this chart repo MUST be
# tagged with the SAME semver as the braghettos/snowplow release it
# ships — chart tag 0.30.111 ships snowplow 0.30.111. Both the
# release-time CRD sync (release-tag.yaml clones snowplow at
# github.ref_name) and the deployed image.tag (deployment.yaml falls
# back to .Chart.AppVersion, which the release CI sets from the tag)
# rely on this. Tagging the chart with a semver that has no matching
# snowplow tag will fail the release build by design.
#
# Usage:
#   sync-crds.sh <path-to-snowplow-repo>          sync in place
#   sync-crds.sh <path-to-snowplow-repo> --check  fail if out of sync
#                                                 (the CI drift gate)
#
# release-tag.yaml clones braghettos/snowplow at the matching release
# tag and runs this (sync mode) before packaging crd-chart, so a chart
# release ALWAYS vendors the crds/ of the snowplow release it ships.
# release-pullrequest.yaml runs this in --check mode against snowplow
# main, to catch a hand-edit to crd-chart/templates/ at PR time.
set -euo pipefail

SNOWPLOW_SRC="${1:-}"
MODE="${2:-sync}"

if [[ -z "$SNOWPLOW_SRC" ]]; then
  echo "usage: sync-crds.sh <path-to-snowplow-repo> [--check]" >&2
  exit 2
fi

SRC_DIR="${SNOWPLOW_SRC%/}/crds"
DST_DIR="$(cd "$(dirname "$0")/.." && pwd)/crd-chart/templates"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: snowplow crds/ not found at $SRC_DIR" >&2
  exit 1
fi
if [[ ! -d "$DST_DIR" ]]; then
  echo "ERROR: crd-chart/templates/ not found at $DST_DIR" >&2
  exit 1
fi

shopt -s nullglob
crd_files=("$SRC_DIR"/*.yaml)
if [[ ${#crd_files[@]} -eq 0 ]]; then
  echo "ERROR: no CRD YAML files in $SRC_DIR" >&2
  exit 1
fi

drift=0
for src in "${crd_files[@]}"; do
  bn="$(basename "$src")"
  dst="$DST_DIR/$bn"
  if [[ "$MODE" == "--check" ]]; then
    if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
      echo "DRIFT: crd-chart/templates/$bn differs from snowplow crds/$bn"
      diff -u "$dst" "$src" || true
      drift=1
    else
      echo "in-sync: $bn"
    fi
  else
    cp "$src" "$dst"
    echo "synced: $bn"
  fi
done

if [[ "$MODE" == "--check" ]]; then
  if [[ "$drift" -ne 0 ]]; then
    echo
    echo "ERROR: crd-chart/templates/ is out of sync with the snowplow repo's crds/."
    echo "       Run 'scripts/sync-crds.sh <snowplow-repo>' and commit the result."
    exit 1
  fi
  echo "OK: crd-chart/templates/ is in sync with the snowplow repo's crds/."
fi
