# Contributing to forail-helm

Thanks for your interest in contributing!

The full contributing guide — git workflow, commit conventions, coding standards, PR process — lives in the [Forail developer docs](https://forail-platform.github.io/dev/contributing.html). Please read it before submitting a pull request.

## What lives here

Helm chart for installing Forail on Kubernetes. The chart is published per release and tagged with both `version` (chart SemVer) and `appVersion` (Forail CalVer).

## Quick start

```bash
git clone https://github.com/forail-platform/forail-helm.git
cd forail-helm
helm lint .
helm template forail . > /tmp/forail.yaml
helm install forail . --namespace forail --create-namespace
```

## Chart-specific guidelines

- **`helm lint` must pass** before commit.
- **`helm template`** with default values and any documented value combinations (e.g. `--set assistant.enabled=true`) must render valid manifests.
- **Version bumps**: chart `version` in [Chart.yaml](./Chart.yaml) follows SemVer; `appVersion` follows the Forail platform CalVer (e.g. `2026.05.0`).
- **CHANGELOG** — every chart-version bump needs a [CHANGELOG.md](./CHANGELOG.md) entry describing what changed in values, templates, or app version.
- **Image references** — keep all image references in `values.yaml` (`image.repository`, `image.tag`) so users can override without forking the chart.

## Reporting bugs

Open an issue with reproduction steps, expected vs. actual behavior, your Kubernetes version, and the chart version.

For security vulnerabilities, see [SECURITY.md](./SECURITY.md) — please do **not** open a public issue.
