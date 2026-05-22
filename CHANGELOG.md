# Changelog

All notable changes to the Forge Helm chart will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart uses SemVer (`version`) plus the upstream Forge CalVer
(`appVersion`).

## [Unreleased]

## [1.0.0] - 2026-05-22

### Changed
- Chart version bumped to **1.0.0** marking platform GA alongside
  `forge-operator` v1.0.0 (multi-cluster control plane + 9 CRDs).
- `appVersion` bumped to **2026.05.0** to track the backend release
  that includes the `0208_driftalertrule_audit_fields` migration fix
  and the `forge-assistant` 2026.05.0 cycle.

## [0.3.0] - 2026-05-08

### Added
- `forge-assistant` deployment (PVC + Service + Deployment) wrapping
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
  `forge-assistant.<ns>.svc.cluster.local:8100` and can be exposed by
  a follow-up middleware/path rule.

## [0.2.0] - 2026-04-29

### Added
- `init.sh` now force-updates the registered Forge Instance to
  `node_type=hybrid` after `provision_instance`, since `forge-web`
  self-registers as `control` on first start and `provision_instance`
  only inserts (it does not update an existing instance). Without
  this fix, jobs error out with `unknown work type
  kubernetes-incluster-auth`.
- `init.sh` now resets the auto-created `default` InstanceGroup off
  `is_container_group=true` after `register_queue`. The Forge
  post-migrate signal sets that flag in k8s deployments, which makes
  the dispatcher route every job through a non-existent
  ContainerGroup.

### Changed
- `task.resources.limits.memory` bumped from **2Gi → 4Gi**. The 2Gi
  limit was OOM-killed during a single Demo Project sync +
  hello_world run because supervisord + dispatcher + Receptor +
  ansible-runner + an EE container together blow past 2 Gi. The
  Receptor work units in `/tmp` die with the pod and Forge cannot
  recover the in-flight job.
- `ingress.host` and CSRF trusted origins switched from `forge.local`
  to `forge.lan`. Avahi/mDNS (`mdns_minimal [NOTFOUND=return]` in
  most desktop Linux distros) hijacks all `.local` lookups and
  bypasses `/etc/hosts`, breaking browser access to the test cluster
  even though `curl` works fine.

## [0.1.0] - 2026-03-02

### Added
- Initial Helm chart wrapping the Forge stack: postgres
  (StatefulSet), redis, OPA, OTel Collector, forge-web, forge-task
  (privileged for podman), forge-init (Job), forge-frontend
- Single Ingress with path-based routing: `/` → frontend,
  `/api`, `/admin`, `/static`, `/sso`, `/websocket` → backend, with
  `/static/forge` precedence so the SPA assets resolve correctly
- ConfigMap rendering of static configs (`settings/`, `scripts/`,
  `receptor/`, `otel/`, `nginx/`) via `Files.Glob`
- `Makefile` with `lint`, `template`, `package`, `install`,
  `upgrade`, `uninstall`, `sync-from-deploy`, `clean` targets
