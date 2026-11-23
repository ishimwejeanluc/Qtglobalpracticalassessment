#!/usr/bin/env bash
# Shared helpers for the release scripts. Source it:  source "$ROOT/scripts/lib.sh"

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$ROOT/docker/.env}"
REGISTRY="${REGISTRY:-registry-1.docker.io}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Load docker/.env: KEY=value lines read as data (never executed); variables already set win.
load_env() {
  [[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found - cp docker/.env.example docker/.env"
  [[ "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")" == "600" ]] \
    || log "WARNING: $ENV_FILE holds secrets - run: chmod 600 $ENV_FILE"
  local key value
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue   # skip comments and blank lines
    [[ -z "${!key:-}" ]] && export "$key=$value"
  done < "$ENV_FILE"
  : "${DOCKERHUB_USER:?set DOCKERHUB_USER in $ENV_FILE}"
  : "${IMAGE_TAG:?set IMAGE_TAG in $ENV_FILE}"
  [[ "$IMAGE_TAG" != "latest" ]] || die "IMAGE_TAG must be a version (e.g. 1.0.0), not 'latest'"
}

# Log in to Docker Hub for images (docker) and charts (helm OCI). The token goes through stdin,
# so it never appears in `ps` or shell history. Without a token, existing logins are used.
registry_login() {
  [[ -n "${DOCKERHUB_TOKEN:-}" ]] || { log "No DOCKERHUB_TOKEN - using existing logins"; return; }
  log "Logging in to Docker Hub as $DOCKERHUB_USER (images and charts)"
  printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USER" --password-stdin >/dev/null
  printf '%s' "$DOCKERHUB_TOKEN" | helm registry login "$REGISTRY" --username "$DOCKERHUB_USER" --password-stdin >/dev/null
}

# Read a top-level field (name, version) from a Chart.yaml
chart_field() { awk -v k="$2:" '$1 == k { gsub(/"/, "", $2); print $2; exit }' "$1/Chart.yaml"; }
