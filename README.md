# forge-helm

[![CI](https://github.com/forgeplatform/forge-helm/actions/workflows/ci.yml/badge.svg)](https://github.com/forgeplatform/forge-helm/actions/workflows/ci.yml)

Kubernetes Helm chart for the Forge automation platform.

Deploys the full stack: PostgreSQL, Redis, OPA, OpenTelemetry Collector,
Forge backend (web + task + init Job), Forge frontend, and an Ingress
that routes `/` to the SPA and `/api`, `/admin`, `/static`, `/sso`,
`/websocket` to the backend.

## Quickstart

Images are published to public `ghcr.io/forgeplatform/*` — no pull secret needed.

```sh
# (Optional) Pre-create a TLS secret for the Ingress:
kubectl create ns forge
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls.key -out tls.crt -subj '/CN=forge.local' \
    -addext 'subjectAltName=DNS:forge.local,DNS:*.forge.local'
kubectl -n forge create secret tls forge-tls --cert=tls.crt --key=tls.key

# Install:
helm install forge . -n forge --create-namespace -f values.yaml
```

If you mirror the images to a private registry, override `images.*.repository` and set
`imagePullSecrets` in your values file.

## Layout

```
forge-helm/
├── Chart.yaml
├── values.yaml
├── Makefile          # lint / template / package / sync-from-deploy
├── templates/        # 14 templates (postgres, redis, opa, otel,
│                       forge-web/task/frontend/init, ingress, ...)
└── files/            # static configs consumed via Helm Files.Get
    ├── settings/     # Forge backend settings.py modules
    ├── scripts/      # init.sh, healthcheck-*.sh, backup/restore
    ├── nginx/        # internal nginx for forge-web
    ├── otel/         # OpenTelemetry Collector config
    └── receptor/     # Receptor mesh config
```

## Sync with forge-deploy

The static config files under `files/` are duplicated from
`forge-deploy` (the docker-compose deployment artifact repo). When the
upstream files change, sync them:

```sh
make sync-from-deploy   # copies from ../forge-deploy/{settings,scripts,...}
git diff                # review
git add files/ && git commit -m "files: sync from forge-deploy"
```

The chart and forge-deploy must therefore be cloned side-by-side at the
same parent directory for `make sync-from-deploy` to work.

## Companion repos

* **forge-deploy** — docker-compose deployment + single-VM Vagrantfile
* **forge-operator** — k8s operator that reconciles JobTemplate /
  Inventory / Credential / Schedule CRDs with the Forge REST API
* **forge-dev-cluster** — 4-VM Vagrant test cluster for chart + operator
  integration testing
