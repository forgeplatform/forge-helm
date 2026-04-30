# Changelog

All notable changes to the Forge Helm chart will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the chart uses SemVer (`version`) plus the upstream Forge CalVer
(`appVersion`).

## [Unreleased]

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
