#!/usr/bin/env bash
# Build and publish everything to Docker Hub: application images, then Helm charts.
#
#   ./scripts/release.sh              # settings and credentials come from docker/.env
#
# Both steps are immutable and idempotent: existing image tags and chart versions are skipped.
# Deploy afterwards:  ./scripts/deploy-k8s.sh   (helmfile, only what changed)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

load_env
registry_login

SKIP_LOGIN=1 "$ROOT/scripts/build-push-images.sh"
SKIP_LOGIN=1 "$ROOT/scripts/publish-charts.sh"
