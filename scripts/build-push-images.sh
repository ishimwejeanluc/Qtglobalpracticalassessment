#!/usr/bin/env bash
# Build and push the application images with a short, IMMUTABLE tag.
#
#   ./scripts/build-push-images.sh         # settings and credentials come from docker/.env
#
# Images:    <DOCKERHUB_USER>/projecthub-api:<IMAGE_TAG>
#            <DOCKERHUB_USER>/projecthub-frontend:<IMAGE_TAG>
# Immutable: a tag that already exists on Docker Hub is never rebuilt or overwritten.
#            To publish a change, bump IMAGE_TAG in docker/.env (e.g. 1.0.0 -> 1.0.1).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
PLATFORM="${PLATFORM:-linux/amd64}"

load_env
[[ "${SKIP_LOGIN:-}" == 1 ]] || registry_login

# build_push <image-name> <context> <dockerfile> [extra build args...]
build_push() {
  local name="$1" context="$2" dockerfile="$3"; shift 3
  local ref="docker.io/${DOCKERHUB_USER}/${name}:${IMAGE_TAG}"

  if docker buildx imagetools inspect "$ref" >/dev/null 2>&1; then
    log "$ref already exists - immutable, skipped (bump IMAGE_TAG to publish changes)"
    return
  fi
  log "Building and pushing $ref"
  docker buildx build --platform "$PLATFORM" --file "$dockerfile" --tag "$ref" --push "$@" "$context"
}

build_push projecthub-api      "$ROOT/app/backend"  "$ROOT/docker/Dockerfile.backend"
build_push projecthub-frontend "$ROOT/app/frontend" "$ROOT/docker/Dockerfile.frontend" --build-arg VITE_API_URL=/api

log "Images: ${DOCKERHUB_USER}/projecthub-{api,frontend}:${IMAGE_TAG}"
