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
  `forail.allowedHosts` defaults to the ingress host (not `"*"`).
- `networkPolicy.enabled` (default false) adds a default-deny ingress policy with
  scoped allows so Postgres/Redis aren't reachable cluster-wide. Enable it on a
  policy-enforcing CNI (Calico/Cilium) — k3s' default flannel does not enforce it.
- `podSecurityContext` and per-workload `securityContext.{web,frontend,assistant}`
  are available for pod hardening (empty by default; validate per image — the
  frontend binds `:80` and needs `NET_BIND_SERVICE` or a non-root port).

## Layout

```
forail-helm/
├── Chart.yaml
├── values.yaml
├── Makefile          # lint / template / package / sync-from-deploy
├── templates/        # 14 templates (postgres, redis, opa, otel,
│                       forail-web/task/frontend/init, ingress, ...)
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
