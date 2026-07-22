# Changelog

All notable changes to the Forail Helm chart will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart uses SemVer (`version`) plus the upstream Forail CalVer
(`appVersion`).

## [Unreleased]

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
