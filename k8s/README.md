# Task 4 – ProjectHub on Kubernetes (Helm + Helmfile)

The application runs in namespace **`qt-spring-app`** as **one Helm release per service**. It is reachable on every node through two entry points:

| Entry point | URL | Routes `/` and `/api` with |
|---|---|---|
| NodePort Service (required) | **`http://<node-ip>:30080`**, e.g. http://192.168.160.95:30080 | NGINX edge (`projecthub-edge`) |
| Gateway API (bonus) | **`http://<node-ip>:30081`**, e.g. http://192.168.160.95:30081 | Gateway + HTTPRoute on Envoy Gateway (`projecthub-gateway`) |

## Layout

```
k8s/
├── namespace.yaml            # namespace (PSA "restricted") + default-deny ingress NetworkPolicy
├── helmfile.yaml.gotmpl      # the 6 releases, chart versions pinned, deploy order ("needs")
├── values/                   # per-release values: image tags from docker/.env, storage node
└── charts/
    ├── projecthub-lib/            # library chart: labels, security contexts, probes,
    │                              # ServiceAccount, Service, PDB, NetworkPolicy helpers
    ├── projecthub-api-chart/      # configmap, deployment, service, pdb, hpa, networkpolicy, serviceaccount
    ├── projecthub-frontend-chart/ # deployment, service, pdb, networkpolicy, serviceaccount
    ├── projecthub-edge-chart/     # configmap (nginx.conf), deployment, service (NodePort), pdb, ...
    ├── projecthub-gateway-chart/  # gatewayclass, envoyproxy, gateway, httproute
    ├── projecthub-mongodb-chart/  # storageclass, persistentvolume, persistentvolumeclaim, service, statefulset, ...
    └── projecthub-valkey-chart/   # deployment, service, networkpolicy, serviceaccount
```

**Separation of concerns:**
- Every template file holds **one resource**.
- Logic shared by all services lives once, in the `projecthub-lib` library chart. Each chart's `serviceaccount.yaml`, `networkpolicy.yaml`, `pdb.yaml` and `service.yaml` is a one-line include.
- Only the parts that really differ (Deployments, ConfigMaps, the StatefulSet, Gateway objects) are written per chart.

### Why separate releases, not one umbrella chart
- **Independent deploys and rollbacks:** each service deploys and rolls back on its own. Rolling back a frontend bug never touches the MongoDB StatefulSet.
- **Separate data tier:** MongoDB and Valkey have their own lifecycle, so they get their own releases.
- **Declarative orchestration:** Helmfile declares all releases and their order in one file. `helmfile apply` upgrades **only the releases that changed** (via helm-diff), and `atomic` rolls back any release whose upgrade fails.

### Why our own MongoDB and Valkey charts
- **MongoDB:** Bitnami's chart now defaults to the `latest` image tag, which breaks our pinned-tag rule. It also expects a dynamic StorageClass, while the exam requires an explicit PV and PVC.
- **Valkey:** the official `valkey-io` chart (v1.0.0) is the production alternative. Here, a small own chart keeps the exact "Redis Deployment + Service" the exam asks for, and it has been proven in the cache-down demo.

## Release flow

```bash
./scripts/release.sh                 # images + charts -> Docker Hub (both immutable)
cd ansible && ansible-playbook playbooks/k8s-app-prereqs.yml   # storage dir, namespace, Secret
cd .. && ./scripts/deploy-k8s.sh --diff        # preview
./scripts/deploy-k8s.sh                      # deploy only what changed, then verify
```

| Step | What happens |
|---|---|
| `scripts/build-push-images.sh` | `ishimwejeanluc/projecthub-{api,frontend}:<IMAGE_TAG>`. An existing tag is never overwritten |
| `scripts/publish-charts.sh` | Vendors `projecthub-lib`, runs `helm lint --strict`, then `helm package` + `helm push` to `oci://registry-1.docker.io/ishimwejeanluc/projecthub-<svc>-chart:<version>`. An existing chart version is never overwritten |
| `playbooks/k8s-app-prereqs.yml` | What Helm can't or shouldn't do: MongoDB's data directory on worker-1 (SSH + sudo), the namespace (PSA + default-deny), and the Secret from `docker/.env` (sent via stdin, so secrets never enter Helm values). **Idempotent: a second run reports `changed=0`** |
| `scripts/deploy-k8s.sh` (by hand) | Preflight (tools, helm-diff, cluster, namespace, Secret), then `helmfile diff` **against the live cluster** (three-way merge), so manual changes like `kubectl scale` are detected and repaired. If nothing differs it stops: no new revisions. Otherwise `helmfile apply`; then checks every release is deployed, all pods are Ready and `/api/health` answers on :30080 and :30081 |
| `helmfile apply` (inside the script) | Pulls the pinned charts from Docker Hub, diffs every release, and upgrades **only those that changed**, in `needs` order. `atomic` rolls a failed release back. With nothing changed it upgrades nothing |

Charts and images live in the **same Docker Hub account**. The `-chart` suffix keeps chart repositories apart from image repositories. To ship a change, bump `IMAGE_TAG` (app code) or the chart `version` (templates), publish, and deploy.

The Helmfile defaults match the current release (`ishimwejeanluc`, image tag `1.0.0`, storage node `c3-k8s-worker-1`). To deploy a new image tag without editing files:
```bash
IMAGE_TAG=1.0.1 helmfile apply
```

## Architecture

```
       :30080 (any node)                         :30081 (any node)
              │                                         │
   projecthub-edge (NGINX x2)           Envoy proxies x2 (envoy-gateway-system)
              │                          Gateway projecthub-gateway + HTTPRoute
              └───────────────┬─────────────────────────┘
                  /api ───────┴─────── /
          projecthub-api (x3)        projecthub-frontend (x2)
            │            │
  projecthub-mongodb   projecthub-valkey
  StatefulSet + local  password, no persistence
  PV/PVC (worker-1)
```

| Exam requirement | Implementation |
|---|---|
| Namespace | `qt-spring-app` (`namespace.yaml`) |
| Deployments / StatefulSet | api, frontend, edge, valkey (Deployments); MongoDB (StatefulSet) |
| Services | ClusterIP for api, frontend and valkey; headless for MongoDB; **NodePort 30080** for the edge |
| ConfigMaps | `projecthub-api-config` (GIN mode, datasource `MONGO_HOST`, DB name, cache settings), `projecthub-edge-nginx` |
| Secrets | `projecthub-secrets` (JWT, MongoDB user and password, Valkey password). The API builds `MONGO_URI` from ConfigMap + Secret |
| PV + PVC | `projecthub-mongodb-pv` (local, 5Gi, `c3-k8s-worker-1`, Retain, kept on uninstall) ↔ `projecthub-mongodb-data` |
| Requests and limits | on every container |
| Memory fits the limit | Go `GOMEMLIMIT=200MiB` under a 256Mi limit (the JVM-heap equivalent); MongoDB `--wiredTigerCacheSizeGB 0.25` under 1Gi |
| Probes | API: startup + readiness + liveness `/api/health`. Frontend: readiness + liveness `/` |
| Gateway API (bonus) | Gateway API CRDs **v1.6.1** (standard) + Envoy Gateway **v1.10.0**, installed by `ansible/playbooks/k8s-cluster.yml` |

### Does the cache need persistent storage? No.
Valkey only holds copies (dashboard statistics and user lookups, with 1–2 minute TTLs). MongoDB is the source of truth, and the API falls back to it on a miss or when Valkey is down. Losing the cache costs latency, never data, so Valkey runs with `--save "" --appendonly no` on an `emptyDir`. MongoDB holds the users and projects and **must** persist. That was proven twice: data survived deleting the MongoDB pod, and it survived the migration from the old single-chart release.

## Resilience (evidence: `monitoring/k8s-resilience-demo.txt`)

| Test | Result |
|---|---|
| API at 3 replicas, one pod deleted while requests flow | **101/101 requests HTTP 200** |
| Valkey scaled to 0 | `/api/health` → `{"status":"ok","database":"up","cache":"down"}`; login OK; **20/20** requests HTTP 200 |
| Valkey restored | `cache` back to `"up"` |

## Production-readiness checklist: what we did and why

The exam asks for a working deployment. On top of that, the charts were reviewed against a **senior platform-engineer checklist** (`k8sreq.md`, "The Platform Engineer's Diagnostic Checklist"). It has three pillars: **Reliability**, **Security**, and **Workflow & Governance**.

For each item below: **what** we did, **why** it matters, and **where** it is in the code.

Legend:
- ✅ done
- 🟡 partly done, the gap explained
- ➖ deliberately not done in this lab, with the reason and the production next step

### Pillar 1: Reliability (keep the app up)

| # | Checklist item | Status | What we did | Why |
|---|---|---|---|---|
| R1 | Requests and limits on every container | ✅ | Every container has both. API: request `50m`/`64Mi`, limit `500m`/`256Mi`. MongoDB: limit `1Gi`, with WiredTiger cache capped at `0.25` GB | **Requests** let the scheduler place pods on a node with room. **Limits** stop one pod (for example a memory leak) from starving the node. Without requests, `kubectl top` and an HPA have nothing to compare against |
| R1b | Runtime memory fits the limit | ✅ | `GOMEMLIMIT=200MiB` under the 256Mi limit; MongoDB `--wiredTigerCacheSizeGB 0.25` under 1Gi | Same idea as setting the JVM heap below the container limit. The runtime frees memory **before** the kernel OOM-kills the pod. By default Go and MongoDB size themselves from the **node's** RAM, not the container's |
| R2 | Readiness and liveness probes with sensible thresholds | ✅ | API: readiness every 10 s, 3 failures. Liveness **lenient** (every 20 s, 6 failures = 2 min). Frontend and edge have both | **Readiness** removes a pod from the Service while it can't answer, so users never hit it. **Liveness** restarts a stuck pod. It is lenient on purpose: `/api/health` returns 503 while MongoDB is down, and a strict liveness would restart **every** API pod during a short database blip, turning a small outage into a big one |
| R3 | Startup probe for slow starters | ✅ | API: 20 × 5 s = 100 s, which is longer than `MONGO_CONNECT_TIMEOUT=90s` | On the first deploy the API waits for MongoDB. Without a startup probe, liveness killed it in that window (we saw restarts). While the startup probe runs, liveness is paused |
| R4 | `replicaCount ≥ 2` for anything that must not go down | ✅ | API **3**, frontend **2**, edge **2** | One replica means any restart, node drain or crash is an outage. Three API pods survive losing one pod (proven: **101/101** requests OK while a pod was deleted) |
| R4b | Exception: the data tier | — | MongoDB **1** (StatefulSet), Valkey **1** | A MongoDB replica set means 3 members, more storage and more complexity than this 3-node lab needs. Valkey is a disposable cache, and the app keeps working without it (proven: **20/20** requests OK with Valkey at 0) |
| R5 | PodDisruptionBudget when replicas > 1 | ✅ | `minAvailable: 1` for api, frontend and edge | During a voluntary disruption (`kubectl drain`, a node upgrade) Kubernetes keeps at least one pod running. **No PDB on the single-replica MongoDB and Valkey**: a `minAvailable: 1` PDB on 1 replica would block every node drain forever |
| R6 | Rolling update `maxUnavailable: 0` | ✅ | All Deployments | A new pod must be **Ready** before an old one is removed, so capacity never drops during an upgrade. With `maxSurge` it costs only one extra pod for a short time |
| R7 | HPA, with `replicas` omitted when the HPA is on | ✅ (off) | The HPA template is in the API chart (2–5 pods, 70% CPU), `autoscaling.enabled: false`. The Deployment writes `replicas:` **only if the HPA is off** | If both Helm and the HPA set `replicas`, every `helm upgrade` resets the count and fights the HPA. It is off here because traffic is flat in the lab, and it would undo the "scale to 3" resilience demo. Turning it on is one value |
| R8 | Topology spread | ✅ (by node) | `topologyKey: kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway` | Replicas land on **different workers**, so losing one VM doesn't take out every pod (visible in `k8s-pods.png`: API pods on worker-1 **and** worker-2). Zone spread isn't possible here because the nodes have no zone label. `ScheduleAnyway` means a full node never blocks a deploy |

### Pillar 2: Security (limit the damage if something is compromised)

| # | Checklist item | Status | What we did | Why |
|---|---|---|---|---|
| S1 | `runAsNonRoot: true` | ✅ | Numeric UIDs: API `10001`, frontend and edge `101`, MongoDB and Valkey `999` | Root in a container is much closer to root on the node. **Numeric** UIDs matter: Kubernetes can only verify "non-root" from a number, and the API image's user `app` is a name, so the chart sets the UID |
| S2 | `readOnlyRootFilesystem: true` | ✅ | Set in the library chart for every pod. Writable paths are explicit `emptyDir` mounts (`/tmp` for NGINX and MongoDB, the data PVC for MongoDB) | An attacker can't drop tools or change binaries in the container. The `emptyDir` mounts document exactly what the app needs to write |
| S3 | `allowPrivilegeEscalation: false` | ✅ | Library chart | Blocks `setuid` binaries from gaining more privileges than the process started with |
| S4 | Drop all Linux capabilities | ✅ | `capabilities.drop: [ALL]`, plus `seccompProfile: RuntimeDefault` | No pod needs a capability: everything listens on ports above 1024 (8080, 27017, 6379). Seccomp blocks dangerous system calls |
| S5 | Dedicated ServiceAccount, no token mounted | ✅ | One ServiceAccount per service, `automountServiceAccountToken: false` | No app pod talks to the Kubernetes API, so none gets a token. A compromised pod then can't query or change the cluster |
| S6 | No secrets in values files or templates | ✅ | Charts use `existingSecret: projecthub-secrets`. Ansible creates that Secret from `docker/.env`, sending the values through stdin with `no_log` | Values files are in Git, and Helm keeps every release's values in its history. A password there would leak in both places. With `existingSecret`, Helm only knows the Secret's **name** |
| S7 | NetworkPolicy limits ingress **and egress** | 🟡 ingress only | `default-deny-ingress` for the whole namespace ([namespace.yaml](namespace.yaml)), plus one allow-list per service: MongoDB and Valkey accept only the API; the API accepts only the edge and Envoy; the frontend accepts only the edge and Envoy; the edge accepts the NodePort | Ingress is where the risk is: the database and cache can't be reached even from inside the cluster, except by the API. **Egress is not restricted yet.** Default-deny egress also blocks DNS, so each policy needs explicit DNS and API→database rules. That is the next hardening step |
| S8 | Namespace Pod Security `restricted` (or baseline) | ✅ | `pod-security.kubernetes.io/enforce: restricted` on `qt-spring-app` | This is the **safety net** for S1–S5: the API server **rejects** any pod that breaks the restricted rules, even one deployed by hand outside Helm |

### Pillar 3: Workflow and governance (safe, repeatable changes)

| # | Checklist item | Status | What we did | Why |
|---|---|---|---|---|
| G1 | Chart version bumped for every change | ✅ enforced | `publish-charts.sh` **refuses** to push a chart version that already exists on Docker Hub | A version must always mean the same content. If `1.0.0` could be overwritten, two clusters "on 1.0.0" could run different templates, and a rollback would not restore what really ran |
| G2 | Chart and image versions pinned (no `latest`) | ✅ | Helmfile pins every chart to `1.0.0`. Images use `IMAGE_TAG=1.0.0` (immutable, same refuse-to-overwrite rule), and base images are pinned by digest | With `latest`, two deploys of the same files can give different results. That is also why we wrote our own MongoDB chart: Bitnami's now defaults to the `latest` tag |
| G3 | `helm unittest` tests | ➖ | Not written | Out of scope for the exam time. The safeguard used instead: `helm lint --strict` + `helmfile diff` before every apply, and the live verification in `deploy-k8s.sh` (all pods Ready, `/api/health` on both entry points) |
| G4 | `helm lint` passes with no warnings | ✅ | `publish-charts.sh` runs `helm lint --strict` and stops on any warning | Catches template and values mistakes **before** anything reaches the registry |
| G5 | Review `helmfile diff` before applying | ✅ | `deploy-k8s.sh` always diffs first. `--diff` stops there (preview only) | You see exactly what will change. If nothing differs, nothing is applied and no new Helm revision is created, so a re-run is truly idempotent |
| G6 | Atomic deploys | ✅ | `helmDefaults: atomic: true, cleanupOnFail: true, wait: true`. On Helm 4 this is `--rollback-on-failure` | A failed upgrade (a pod never becomes Ready) is rolled back automatically, so the cluster is never left half-upgraded. `wait` means "success" really means "all pods Ready" |
| G7 | Secrets encrypted with sops and committed | ➖ | Secrets live in the git-ignored `docker/.env` (mode 600). Ansible creates the Kubernetes Secret from it | The lab has no key management (age/GPG, KMS) to store a decryption key safely. **Production:** sops-encrypted values or the External Secrets Operator reading from a vault |
| G8 | Drift detection on a schedule | 🟡 manual | `./scripts/deploy-k8s.sh --diff` diffs against the **live** cluster (`HELM_DIFF_THREE_WAY_MERGE=true`), so a manual `kubectl scale` is detected. A plain run repairs it, upgrading only the changed release | Without three-way merge, helm-diff only compares with Helm's stored record and **misses** manual changes. We tested exactly that case. Only the schedule is missing (there is no CI here); in production it becomes a cron job that alerts on exit code 2 |

**The golden rule we followed:** Helm owns every resource it created. Nothing in `qt-spring-app` is changed by hand with `kubectl edit`.
- The resilience demo changes the cluster on purpose (scale, delete a pod, stop the cache), then **restores** it, so a later `--diff` reports no changes.
- When a manual change was found that we wanted to keep (`replicaCount: 3`), it was **written into the chart**, not left as drift.
