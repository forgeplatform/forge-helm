# forail-helm

[![CI](https://github.com/forail-platform/forail-helm/actions/workflows/ci.yml/badge.svg)](https://github.com/forail-platform/forail-helm/actions/workflows/ci.yml)

Kubernetes Helm chart for the Forail automation platform.

Deploys the full stack: PostgreSQL, Redis, OPA, OpenTelemetry Collector,
Forail backend (web + task + init Job), Forail frontend, and an Ingress
that routes `/` to the SPA and `/api`, `/admin`, `/static`, `/sso`,
`/websocket` to the backend.

## Quickstart

Images are published to public `ghcr.io/forail-platform/*` — no pull secret needed.

```sh
# (Optional) Pre-create a TLS secret for the Ingress:
kubectl create ns forail
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt -subj '/CN=forail.local' \
    -addext 'subjectAltName=DNS:forail.local,DNS:*.forail.local'
kubectl -n forail create secret tls forail-tls --cert=tls.crt --key=tls.key

# Install (admin password is required — install fails without it):
helm install forail . -n forail --create-namespace -f values.yaml \
    --set secrets.forailAdminPassword="$(openssl rand -base64 24)"
```

If you mirror the images to a private registry, override `images.*.repository` and set
`imagePullSecrets` in your values file.

## Secure defaults & breaking changes

This chart ships **no working secret defaults**:

- `secrets.postgresPassword`, `secrets.forailSecretKey` and
  `secrets.forailBroadcastWebsocketSecret` are **auto-generated** on first
  install and reused across upgrades — leave them empty unless you want to pin
  explicit values.
- `secrets.forailAdminPassword` is **required**; `helm install` fails if unset.
- `forail-task` runs **non-privileged by default**. The podman-in-pod job
  execution path needs privileges — enable it explicitly and, ideally, isolate
  such workers onto dedicated tainted nodes:

  ```sh
  --set task.privileged=true --set task.hostCgroup=true
  ```

- Session cookies are `Secure` by default (`forail.cookieSecure: "true"`) and
  `forail.allowedHosts` defaults to the ingress host plus `127.0.0.1,localhost`
  (not `"*"`). **Keep the loopback entries** — the liveness/readiness probes call
  the API on `127.0.0.1`, and Django answers `400 DisallowedHost` without them,
  which crash-loops `forail-web`.
- `networkPolicy.enabled` (default false) adds a default-deny ingress policy with
  scoped allows so Postgres/Redis aren't reachable cluster-wide. Enable it on a
  policy-enforcing CNI (Calico/Cilium) — k3s' default flannel does not enforce it.
- `podSecurityContext` and per-workload `securityContext.{web,frontend,assistant}`
  are available for pod hardening (empty by default; validate per image — the
  frontend binds `:80` and needs `NET_BIND_SERVICE` or a non-root port).
- **`assistant.storage.size` dropped 20Gi → 5Gi** when the model server moved to
  its own claim. PVCs cannot shrink, so an existing install with the assistant
  enabled keeps its 20Gi claim and the upgrade fails on the immutable field —
  delete `forail-assistant-data` (the vector index rebuilds itself) or pin
  `--set assistant.storage.size=20Gi`. Fresh installs are unaffected.

## Running jobs in the cluster

Automation jobs run as pods in a Kubernetes **container group**: `forail-task`
asks receptor to create, watch and delete one pod per job. Three pieces must be
in place, all shipped by the chart:

1. **Pod RBAC** — `serviceAccount.create` and `rbac.create` (both default true)
   render a `forail` ServiceAccount and a *namespaced* `forail-job-runner`
   `Role`/`RoleBinding` covering `pods` and `pods/log|attach|exec`. Web, task and
   the init Job run under that account. Turn them off only when you run jobs on
   an external execution node and want no in-cluster job pods; otherwise every
   launch fails with `pods is forbidden ... cannot list resource "pods"` and the
   job stays pending.
2. **Namespace** — the `MY_POD_NAMESPACE` downward-API env makes job pods land in
   the release namespace, which is exactly where the Role grants access.
3. **Receptor worktype** — `files/receptor/receptor.conf` registers
   `kubernetes-incluster-auth` (`authmethod: incluster`). Without it launches
   fail at 0s with `unknown work type kubernetes-incluster-auth`.

The podman-in-pod execution path additionally needs `--set task.privileged=true
--set task.hostCgroup=true` (see the secure defaults above).

## AI assistant (optional)

Off by default (`assistant.enabled=false`). When enabled it renders **two**
Deployments, not one:

| Workload | Contains | Claim |
|----------|----------|-------|
| `forail-assistant` | FastAPI + embedded ChromaDB | `forail-assistant-data`, 5Gi |
| `forail-assistant-ollama` | the model server, `images.assistantOllama` | `forail-assistant-ollama-models`, 20Gi |

They are split so that only the model server needs a GPU and a large volume;
the API stays schedulable on any node. Ollama has no authentication, so its
Service is ClusterIP and only the API talks to it.

```sh
# CPU (default)
helm upgrade forail . -n forail --set assistant.enabled=true

# GPU — requires a node advertising nvidia.com/gpu and the NVIDIA device plugin
helm upgrade forail . -n forail \
    --set assistant.enabled=true \
    --set assistant.ollama.gpu.enabled=true
```

`assistant.ollama.gpu.enabled` requests `nvidia.com/gpu`, which pins that pod
to a node advertising the device — leave it off until the cluster has one, or
the pod stays `Pending`. `images.assistantOllama.tag` is pinned deliberately:
the assistant image used to carry a binary copied out of `ollama/ollama:latest`,
and an upstream layout change broke inference without a line of our code
changing. Bump it on purpose.

## Layout

```
forail-helm/
├── Chart.yaml
├── values.yaml
├── Makefile          # lint / template / package / sync-from-deploy
├── templates/        # 16 templates (postgres, redis, opa, otel,
│                       forail-web/task/frontend/init, ingress, rbac, ...)
└── files/            # static configs consumed via Helm Files.Get
    ├── settings/     # Forail backend settings.py modules
    ├── scripts/      # init.sh, healthcheck-*.sh, backup/restore
    ├── nginx/        # internal nginx for forail-web
    ├── otel/         # OpenTelemetry Collector config
    └── receptor/     # Receptor mesh config
```

## Sync with forail-deploy

The static config files under `files/` are duplicated from
`forail-deploy` (the docker-compose deployment artifact repo). When the
upstream files change, sync them:

```sh
make sync-from-deploy   # copies from ../forail-deploy/{settings,scripts,...}
git diff                # review
git add files/ && git commit -m "files: sync from forail-deploy"
```

The chart and forail-deploy must therefore be cloned side-by-side at the
same parent directory for `make sync-from-deploy` to work.

## Companion repos

* **forail-deploy** — docker-compose deployment + single-VM Vagrantfile
* **forail-operator** — k8s operator that reconciles JobTemplate /
  Inventory / Credential / Schedule CRDs with the Forail REST API
* **forail-dev-cluster** — 4-VM Vagrant test cluster for chart + operator
  integration testing
