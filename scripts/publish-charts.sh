#!/usr/bin/env bash
# Package the service charts and push them to Docker Hub as OCI artifacts.
#
#   ./scripts/publish-charts.sh           # credentials come from docker/.env
#
# Charts:    oci://registry-1.docker.io/<DOCKERHUB_USER>/projecthub-<service>-chart:<version>
#            (the "-chart" suffix keeps chart repositories apart from the image repositories)
# Library:   projecthub-lib is not published on its own: it is vendored into every chart package.
# Immutable: a chart version that already exists is never overwritten.
#            To publish a template change, bump "version" in that chart's Chart.yaml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
CHARTS_DIR="$ROOT/k8s/charts"
DIST_DIR="$ROOT/k8s/dist"          # packaged .tgz files (git-ignored)

load_env
[[ "${SKIP_LOGIN:-}" == 1 ]] || registry_login
OCI="oci://${REGISTRY}/${DOCKERHUB_USER}"
mkdir -p "$DIST_DIR"

for chart in "$CHARTS_DIR"/projecthub-*-chart; do
  name="$(chart_field "$chart" name)"
  version="$(chart_field "$chart" version)"

  log "$name $version: vendoring the library and linting"
  helm dependency update "$chart" >/dev/null
  helm lint --strict "$chart" >/dev/null || die "helm lint failed for $name"

  if helm show chart "$OCI/$name" --version "$version" >/dev/null 2>&1; then
    log "$OCI/$name:$version already exists - immutable, skipped (bump the chart version to publish changes)"
    continue
  fi
  helm package "$chart" --destination "$DIST_DIR" >/dev/null
  helm push "$DIST_DIR/$name-$version.tgz" "$OCI"
done

log "Charts published under $OCI"
