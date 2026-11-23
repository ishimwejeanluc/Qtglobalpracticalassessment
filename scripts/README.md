# scripts/

All scripts read their settings and credentials from **`docker/.env`** (git-ignored, `chmod 600`), and run from the repository root.

| Script | What it does | When |
|---|---|---|
| `release.sh` | **Publishes everything** to Docker Hub: runs `build-push-images.sh`, then `publish-charts.sh` (one login) | After changing app code or a chart |
| `build-push-images.sh` | Builds and pushes `projecthub-{api,frontend}:<IMAGE_TAG>` (multi-stage Dockerfiles in `docker/`) | Images only |
| `publish-charts.sh` | Lints, packages and pushes the Helm charts in `k8s/charts/` to `oci://registry-1.docker.io/<user>/projecthub-<svc>-chart:<version>` | Charts only |
| `deploy-k8s.sh` | Deploys the whole stack with **helmfile**, pulling the charts from Docker Hub. `--diff` previews only | After a release, or to check the cluster is in sync |
| `resilience-demo.sh` | Task 4 evidence: scales the API to 3 and deletes a pod under load, then stops the cache | For the README / exam |
| `lib.sh` | Shared helpers (`load_env`, `registry_login`, `log`, `die`, `chart_field`). Sourced, never run | — |

**Idempotent and immutable:**
- Image tags and chart versions that already exist on Docker Hub are never rebuilt or overwritten. Bump `IMAGE_TAG` in `docker/.env`, or `version` in a `Chart.yaml`, to publish a change.
- `deploy-k8s.sh` applies nothing when the cluster already matches, so no new Helm revisions are created.
- `deploy-k8s.sh` diffs against the **live** cluster (`HELM_DIFF_THREE_WAY_MERGE=true`). A manual change such as `kubectl scale deploy/projecthub-valkey --replicas=0` is detected and repaired, and only that release is upgraded.
- `resilience-demo.sh` changes the cluster on purpose (it stops Valkey), then restores it, so the cluster matches Helm again when it ends.

```bash
./scripts/release.sh                                            # 1. publish images + charts
(cd ansible && ansible-playbook playbooks/k8s-app-prereqs.yml)  # 2. fresh cluster or new secrets only
./scripts/deploy-k8s.sh                                         # 3. deploy only what changed
KUBECONFIG=ansible/kubeconfig ./scripts/resilience-demo.sh > monitoring/k8s-resilience-demo.txt
```
