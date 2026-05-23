# Security Policy

## Supported Versions

The latest released chart version receives security fixes. See [CHANGELOG.md](./CHANGELOG.md) for releases.

| Chart Version | Supported |
|---------------|-----------|
| 1.0.x | Yes |
| < 1.0 | No  |

## Reporting a Vulnerability

Please report security issues privately to **office@krletron.xyz**.

Do **not** open a public GitHub issue for suspected vulnerabilities.

Include:

- Chart version affected
- Insecure default or template issue
- Steps to reproduce
- Suggested remediation if you have one

## Disclosure Timeline

- **48 hours** — acknowledgement of report
- **7 days** — initial assessment and severity classification
- **30 days** — fix released or mitigation provided for critical/high severity
- **90 days** — public disclosure after fix is available

## Scope

In scope:

- Chart templates and default values that produce insecure manifests
- Secret handling and ServiceAccount/RBAC defaults
- Insecure network policies, missing security contexts, privileged containers by default

Out of scope:

- Vulnerabilities in the application images themselves (report to forge-backend / forge-frontend / etc.)
- User-supplied values that override safe defaults
