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

# Install:
helm install forail . -n forail --create-namespace -f values.yaml
```

If you mirror the images to a private registry, override `images.*.repository` and set
`imagePullSecrets` in your values file.

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
