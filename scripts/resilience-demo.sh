#!/usr/bin/env bash
# Task 4 resilience demonstration (output is saved as evidence for the README).
#   A) scale the API to 3 replicas, delete one pod while traffic flows -> no failed requests
#   B) stop the cache (Valkey) -> the app keeps working and /api/health reports "cache": "down"
#
#   KUBECONFIG=ansible/kubeconfig ./scripts/resilience-demo.sh [http://<node-ip>:30080]
set -euo pipefail

NS=qt-spring-app
URL="${1:-http://192.168.160.95:30080}"
API=deployment/projecthub-api
CACHE=deployment/projecthub-valkey
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

step() { printf '\n\033[1m### %s\033[0m\n' "$*"; }
run()  { printf '$ %s\n' "$*"; "$@"; }

login_token() {
  curl -s -X POST "$URL/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"email":"admin@qt.rw","password":"Admin@123"}' | jq -r .token
}

# Send a request every 0.2s for N seconds; record one HTTP status code per line in $LOG
traffic() {
  local seconds="$1" token="$2" end=$((SECONDS + $1))
  : > "$LOG"
  while (( SECONDS < end )); do
    curl -s -o /dev/null -m 3 -w '%{http_code}\n' "$URL/api/projects" -H "Authorization: Bearer $token" >> "$LOG" || echo 000 >> "$LOG"
    sleep 0.2
  done
}

summary() {
  local total ok
  total=$(wc -l < "$LOG" | tr -d ' '); ok=$(grep -c '^200$' "$LOG" || true)
  printf 'Requests: %s | HTTP 200: %s | failed: %s\n' "$total" "$ok" "$((total - ok))"
  sort "$LOG" | uniq -c | sed 's/^/  status /'
}

echo "Target: $URL  ($(date -u '+%F %T UTC'))"
TOKEN="$(login_token)"

step "A1. Scale the API to 3 replicas"
run kubectl scale "$API" -n "$NS" --replicas=3
run kubectl rollout status "$API" -n "$NS" --timeout=120s
run kubectl get pods -n "$NS" -l app.kubernetes.io/name=api -o wide

step "A2. Delete one API pod while requests are flowing"
traffic 25 "$TOKEN" &
TRAFFIC_PID=$!
sleep 3
VICTIM="$(kubectl get pods -n "$NS" -l app.kubernetes.io/name=api -o jsonpath='{.items[0].metadata.name}')"
run kubectl delete pod "$VICTIM" -n "$NS" --wait=false
sleep 2
run kubectl get pods -n "$NS" -l app.kubernetes.io/name=api -o wide
wait "$TRAFFIC_PID"
run kubectl rollout status "$API" -n "$NS" --timeout=120s
run kubectl get pods -n "$NS" -l app.kubernetes.io/name=api -o wide
step "A3. Result: requests during the pod deletion"
summary

step "B1. Stop the cache (scale Valkey to 0)"
run curl -s "$URL/api/health"; echo
run kubectl scale "$CACHE" -n "$NS" --replicas=0
run kubectl wait pods -n "$NS" -l app.kubernetes.io/name=valkey --for=delete --timeout=90s
run kubectl get pods -n "$NS"

step "B2. The application still works without the cache"
run curl -s "$URL/api/health"; echo
TOKEN="$(login_token)"
printf 'Fresh login without cache: %s\n' "$([[ "$TOKEN" == ey* ]] && echo OK || echo FAILED)"
traffic 10 "$TOKEN"
summary

step "B3. Restore the cache"
run kubectl scale "$CACHE" -n "$NS" --replicas=1
run kubectl rollout status "$CACHE" -n "$NS" --timeout=120s
sleep 6   # the API reconnects to the cache in the background (every 5s)
run curl -s "$URL/api/health"; echo
