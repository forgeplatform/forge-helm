# Changelog

All notable changes to the Forail Helm chart will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart uses SemVer (`version`) plus the upstream Forail CalVer
(`appVersion`).

## [Unreleased]

### Security
- **Redis now requires a password.** It ran `redis-server --appendonly yes` and
  nothing else, on a ClusterIP Service, so any pod that could route to it could
  read and write the cache, the task queue and the websocket channel layer — or
  empty all three with one `FLUSHALL`. The password is generated on first install
  and reused on upgrade; it is passed through the environment rather than args,
  and the probes authenticate via `REDISCLI_AUTH`, so it appears in neither the
  pod spec nor a command line.
- **The assistant requires a bearer token.** `FORAIL_ASSISTANT_CHAT_TOKEN` was
  unset, which the assistant reads as "no authentication", and the chart passed
  only the model and log level — so `assistant.enabled=true` gave a chat endpoint
  open to every pod in the cluster, answering with indexed documentation. The
  chart still does not route it through the Ingress.
- **Every workload drops all capabilities and refuses privilege escalation.**
  `podSecurityContext` and the `securityContext.*` keys were empty, and six
  workloads had no key at all. The frontend keeps `NET_BIND_SERVICE` for `:80`.
  `runAsNonRoot` and `readOnlyRootFilesystem` are documented but not defaulted —
  both depend on what an image writes and which user it starts as.
- **`forail.tenancyEnabled=true` now requires `forail.tenancy.rls=true`.** The
  single switch the chart offered turned on quotas, branding and isolation
  auditing while row-level security stayed off with no value to set, so an
  install could look multi-tenant with nothing enforcing a boundary. Adds
  `forail.tenancy.{rls,strictIsolation,rateLimiting}`; RLS defaults to true.

### Fixed
- **The default install could not run a job.** `forail.node.type` defaulted to
  `hybrid` (podman inside the task pod) while `task.privileged` defaulted to
  false — the one combination where podman fails on the overlay mount and every
  job stays `Pending`. The default is now `control`: each job runs as its own
  Kubernetes pod through receptor's `kubernetes-incluster-auth` work type, which
  the chart already shipped everything for. `hybrid` without privileges now fails
  the render instead of installing quietly. `init.sh` no longer forces the
  default instance group back to a regular group regardless of node type.

### Changed
- `images.opa` and `images.otelCollector` are pinned. Neither pin changes what
  runs today: the collector's `latest` genuinely moves (rebuilt 2026-08-18, now
  `0.159.0`), while OPA's `latest-rootless` turned out to be a frozen orphan —
  upstream stopped publishing `-rootless` after `0.58.0` in October 2023.

### Added
- **`forail-assistant-ollama` Deployment, Service and PVC.** The model server is
  no longer part of the assistant image; it runs beside it from
  `images.assistantOllama` (`ollama/ollama`, pinned). The Service is ClusterIP —
  Ollama has no authentication, so only the API is allowed to reach it.
- `assistant.ollama.gpu.enabled` requests `nvidia.com/gpu` **on that pod alone**,
  so only the model server has to land on a GPU node while the API stays
  schedulable anywhere. Off by default: the request pins the pod to a node
  advertising the device, so without one the pod stays `Pending`.
- `assistant.ollama.{nodeSelector,tolerations,storage,resources}` for placing and
  sizing the model server independently of the API.

### Changed
- `images.assistantOllama` is pinned to `ollama/ollama:0.30.10` rather than
  tracking `latest`. The assistant image used to carry a binary copied out of
  `latest`, and an upstream layout change broke inference silently — the server
  answered `/api/tags` so the health check passed, while every generation
  returned 500. Bump this tag deliberately.
- `assistant.resources` drops to `512Mi/250m` requests and `2Gi/1000m` limits:
  inference left this pod, so the budget only has to cover Chroma, uvicorn and
  the first-boot indexing spike.

### Breaking
- **`assistant.storage.size` 20Gi → 5Gi.** Model blobs moved to
  `forail-assistant-ollama-models` (20Gi), so the index claim is now sized by
  the corpus. PVCs cannot shrink: an existing install with `assistant.enabled=true`
  will fail the upgrade on the immutable field. Either delete the
  `forail-assistant-data` claim — the vector index rebuilds itself from
  `docs_to_index/`, nothing irreplaceable is stored there — or keep the old size
  with `--set assistant.storage.size=20Gi`. Fresh installs need no action.

## [2026.7.1] - 2026-07-26

### Fixed
- **An upgrade no longer leaves the `default` queue unable to run anything.**
  `register_queue` assigns instances only when it creates the group, so on an
  upgrade it printed `Instance Group already registered default` and assigned
  nothing — and an empty regular instance group accepts job launches and never
  runs them. The init Job now asserts membership itself, alongside the
  container-group flag it already asserted.

### Changed
- `images.backend.tag` pinned to `2026.07.1`, which carries the matching backend
  fix: the task pod used to re-register itself as `control` and flip `default`
  back to a ContainerGroup on every start, undoing what this Job sets. The
  frontend stays at `2026.07.0` — it is unchanged.

## [2026.7.0] - 2026-07-25

### Added
- **Job-execution RBAC** (`templates/rbac.yaml`): a `forail` ServiceAccount plus
  a namespaced `Role`/`RoleBinding` (`forail-job-runner`) granting
  `pods` + `pods/log|attach|exec` in the release namespace, and a
  `MY_POD_NAMESPACE` downward-API env so the Kubernetes container group launches
  job pods there instead of `default`. Web, task and the init Job now run under
  that account. Without it every launch failed with
  `pods is forbidden ... cannot list resource "pods"` and the job stayed pending.
  Toggles: `serviceAccount.create` / `serviceAccount.name` / `rbac.create`.
- **Receptor `kubernetes-incluster-auth` worktype** in
  `files/receptor/receptor.conf` — the mesh config previously declared only the
  `local` worktype, so in-cluster launches errored immediately with
  `unknown work type kubernetes-incluster-auth`.

### Fixed
- **Loopback hosts kept in `forail.allowedHosts`** (`forail.lan,127.0.0.1,localhost`).
  The in-cluster liveness/readiness probes curl `http://127.0.0.1:8013/api/v2/ping/`;
  with the ingress host alone Django answered `400 DisallowedHost`, the probe
  failed and `forail-web` crash-looped. Add your own hosts to the list rather
  than replacing the loopback entries.
- **Chart render checks in CI** pass a throwaway `secrets.forailAdminPassword`,
  so the now-required password does not fail `helm lint` / `helm template`.
- **In-cluster callers are no longer rejected by `forail.allowedHosts`.** Clients
  that reach the API through the `forail-web` Service send the Service DNS name
  as their `Host`, which the hardened list did not cover, so Django answered
  `400` — the documented forail-operator install
  (`--set forail.url=http://forail-web.<ns>.svc.cluster.local:8013`) could not
  resolve a single object. The chart now appends `forail-web`,
  `forail-web.<ns>`, `forail-web.<ns>.svc` and `forail-web.<ns>.svc.cluster.local`
  to whatever `forail.allowedHosts` is set to. Unknown hosts are still rejected.

### Security
- **No working secret defaults**: `postgresPassword`, `forailSecretKey` and
  `forailBroadcastWebsocketSecret` are auto-generated on first install and
  reused across upgrades (via a Secret `lookup`). `forailAdminPassword` is now
  **required** — `helm install` fails unless you provide one.
- **`forail-task` defaults to non-privileged** with no host cgroup mount. Opt in
  for the podman-in-pod execution path: `--set task.privileged=true --set
  task.hostCgroup=true`.
- **Secure cookies on by default** (`forail.cookieSecure: "true"`) and
  `forail.allowedHosts` defaults to the ingress host plus loopback instead of
  `"*"`.
- **Opt-in NetworkPolicy** (`networkPolicy.enabled`, default false): default-deny
  ingress with scoped allows so Postgres/Redis aren't reachable cluster-wide.
- **Per-workload `securityContext` / `podSecurityContext`** values wired into
  web / frontend / assistant (empty by default, pending per-image validation).

## [2026.06.0] - 2026-06-14

### Changed
- **Renamed `forge` → `forail`** across the entire project (organization `forgeplatform` → `forail-platform`): image references and chart, image references (`ghcr.io/forail-platform/forail-*`), CLI, and all documentation/URLs. The GitHub organization and repositories were renamed to match.
- Versioning unified across all platform components to CalVer `2026.06.0`.


## [1.0.0] - 2026-05-22

### Changed
- Chart version bumped to **1.0.0** marking platform GA alongside
  `forail-operator` v1.0.0 (multi-cluster control plane + 9 CRDs).
- `appVersion` bumped to **2026.05.0** to track the backend release
  that includes the `0208_driftalertrule_audit_fields` migration fix
  and the `forail-assistant` 2026.05.0 cycle.

## [0.3.0] - 2026-05-08

### Added
- `forail-assistant` deployment (PVC + Service + Deployment) wrapping
  the all-in-one image that bundles Ollama, ChromaDB, and the FastAPI
  service. Disabled by default (`assistant.enabled=false`); flip on
  with `--set assistant.enabled=true` and adjust `assistant.model`,
  `assistant.storage.size`, and `assistant.resources` to match the
  target cluster.
- `assistant.storage.size` (default **20Gi**) provisions the PVC that
  holds the Ollama model cache and Chroma vector store, so the model
  is not re-pulled on every pod restart.
- `startupProbe` with `failureThreshold: 30` (≈5 min budget) accounts
  for the first-boot model pull + document indexing without the
  liveness probe killing the pod mid-bootstrap.

### Notes
- Ingress routing for the assistant is intentionally out of scope of
  this release; the Service is reachable via cluster DNS at
  `forail-assistant.<ns>.svc.cluster.local:8100` and can be exposed by
  a follow-up middleware/path rule.

## [0.2.0] - 2026-04-29

### Added
- `init.sh` now force-updates the registered Forail Instance to
  `node_type=hybrid` after `provision_instance`, since `forail-web`
  self-registers as `control` on first start and `provision_instance`
  only inserts (it does not update an existing instance). Without
  this fix, jobs error out with `unknown work type
  kubernetes-incluster-auth`.
- `init.sh` now resets the auto-created `default` InstanceGroup off
  `is_container_group=true` after `register_queue`. The Forail
  post-migrate signal sets that flag in k8s deployments, which makes
  the dispatcher route every job through a non-existent
  ContainerGroup.

### Changed
- `task.resources.limits.memory` bumped from **2Gi → 4Gi**. The 2Gi
  limit was OOM-killed during a single Demo Project sync +
  hello_world run because supervisord + dispatcher + Receptor +
  ansible-runner + an EE container together blow past 2 Gi. The
  Receptor work units in `/tmp` die with the pod and Forail cannot
  recover the in-flight job.
- `ingress.host` and CSRF trusted origins switched from `forail.local`
  to `forail.lan`. Avahi/mDNS (`mdns_minimal [NOTFOUND=return]` in
  most desktop Linux distros) hijacks all `.local` lookups and
  bypasses `/etc/hosts`, breaking browser access to the test cluster
  even though `curl` works fine.

## [0.1.0] - 2026-03-02

### Added
- Initial Helm chart wrapping the Forail stack: postgres
  (StatefulSet), redis, OPA, OTel Collector, forail-web, forail-task
  (privileged for podman), forail-init (Job), forail-frontend
- Single Ingress with path-based routing: `/` → frontend,
  `/api`, `/admin`, `/static`, `/sso`, `/websocket` → backend, with
  `/static/forail` precedence so the SPA assets resolve correctly
- ConfigMap rendering of static configs (`settings/`, `scripts/`,
  `receptor/`, `otel/`, `nginx/`) via `Files.Glob`
- `Makefile` with `lint`, `template`, `package`, `install`,
  `upgrade`, `uninstall`, `sync-from-deploy`, `clean` targets
