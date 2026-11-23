#!/usr/bin/env bash
# Deploy the whole ProjectHub stack to Kubernetes with helmfile (one Helm release per service).
#
#   ./scripts/deploy-k8s.sh           # deploy only what changed, then verify
#   ./scripts/deploy-k8s.sh --diff    # preview only, change nothing
#
# Idempotent: helmfile diff runs first; when the cluster already matches the charts nothing is
# applied (no new Helm revisions). Otherwise helmfile apply upgrades only the changed releases, in
# "needs" order, and rolls a failed release back (atomic).
#
# Before the first deploy (fresh cluster, or after changing secrets in docker/.env):
#   cd ansible && ansible-playbook playbooks/k8s-app-prereqs.yml   # storage dir, namespace, Secret
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

NAMESPACE=qt-spring-app
SECRET=projecthub-secrets
HELMFILE="$ROOT/k8s/helmfile.yaml.gotmpl"
ENTRYPOINTS=(30080 30081)         # NGINX edge NodePort, Gateway API NodePort
export KUBECONFIG="${KUBECONFIG:-$ROOT/ansible/kubeconfig}"
# Diff against the LIVE cluster, not only Helm's stored release record: manual drift
# (e.g. "kubectl scale ... --replicas=0") is then detected and repaired by the apply.
export HELM_DIFF_THREE_WAY_MERGE=true

MODE=apply
case "${1:-}" in
  "") ;;
  --diff) MODE=diff ;;
  -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
  *) die "unknown option: $1 (use --diff or nothing)" ;;
esac

# ---------- Preflight ----------
preflight() {
  local tool
  for tool in kubectl helm helmfile curl; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
  done
  helm plugin list 2>/dev/null | grep -q '^diff' \
    || die "helm-diff plugin missing: helm plugin install https://github.com/databus23/helm-diff --version v3.15.15 --verify=false"
  [[ -f "$KUBECONFIG" ]] || die "kubeconfig not found: $KUBECONFIG (run ansible/playbooks/k8s-cluster.yml)"
  kubectl get --raw=/readyz >/dev/null 2>&1 || die "cluster not reachable with $KUBECONFIG"

  local prereq="run: cd ansible && ansible-playbook playbooks/k8s-app-prereqs.yml"
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || die "namespace $NAMESPACE missing - $prereq"
  kubectl get secret "$SECRET" -n "$NAMESPACE" >/dev/null 2>&1 || die "secret $SECRET missing - $prereq"
}

# ---------- Verification ----------
verify() {
  log "Releases"
  helm list -n "$NAMESPACE"
  local broken
  broken="$(helm list -n "$NAMESPACE" --failed --pending --short)"
  [[ -z "$broken" ]] || die "releases failed or pending: $broken"

  log "Waiting for all pods to be ready"
  kubectl wait pods --all -n "$NAMESPACE" --for=condition=Ready --timeout=300s >/dev/null
  kubectl get pods -n "$NAMESPACE" -o wide

  local node_ip port health
  node_ip="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
  log "Entry points"
  for port in "${ENTRYPOINTS[@]}"; do
    health="$(curl -s -m 10 --retry 10 --retry-delay 3 --retry-all-errors "http://$node_ip:$port/api/health")" \
      || die "http://$node_ip:$port is not answering"
    printf '  http://%s:%s  ->  %s\n' "$node_ip" "$port" "$health"
  done
}

# ---------- Main ----------
load_env              # DOCKERHUB_USER and IMAGE_TAG from docker/.env (read by the helmfile)
preflight
log "Cluster: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')  images: $DOCKERHUB_USER/*:$IMAGE_TAG"

log "helmfile diff"
set +e
helmfile --quiet --file "$HELMFILE" diff --detailed-exitcode --suppress-secrets
rc=$?
set -e
case "$rc" in
  0) log "Cluster already matches the charts - nothing to deploy" ;;
  2) if [[ "$MODE" == diff ]]; then log "Changes found (preview only, nothing applied)"; exit 0; fi
     log "helmfile apply (only the releases above)"
     helmfile --quiet --file "$HELMFILE" apply --suppress-secrets ;;
  *) die "helmfile diff failed (exit $rc)" ;;
esac

[[ "$MODE" == diff ]] || verify
