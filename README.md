# terraform-kubernetes-monitoring

Terraform module that installs cluster monitoring (kube-prometheus-stack, optional
Grafana Mimir, and an optional Grafana HTTPRoute). **kube-prometheus-stack is
always installed**; Mimir and the public Grafana route are optional.

Providers (`helm`, `kubernetes`, `kubectl`) are configured by the **caller**.

This module only **deploys** the monitoring stack. Grafana content (service
accounts, folders, dashboards) is managed separately by
[`terraform-grafana-config`](https://github.com/HobOps/terraform-grafana-config),
which consumes this module's `grafana_admin_password` output through the
caller-configured `grafana` provider — keeping the dependency graph acyclic.

## Components

| Input | Component |
|-------|-----------|
| (always) | kube-prometheus-stack (Prometheus, Grafana, optional Alertmanager) |
| `enable_mimir` | Grafana Mimir (central long-term store; bundled MinIO by default) |
| `enable_blackbox_exporter` | prometheus-blackbox-exporter (+ optional probe targets) |
| `enable_ipmi_exporter` | prometheus-ipmi-exporter (local OPENIPMI; privileged root + `/dev`) |
| `enable_smartctl_exporter` | prometheus-smartctl-exporter (DaemonSet; disk SMART) |
| `grafana_hostname` | Gateway API HTTPRoute to Grafana |
| `grafana_google_auth` | Grafana login with Google OAuth (credentials from an existing Secret) |
| `remote_write_url` | Prometheus remote_write to a central Mimir (or other backend) |

> **metrics-server:** not installed by this module. On k3s it usually ships in
> `kube-system`; elsewhere install it only if you need `kubectl top` / HPA.

## Grafana metrics backend

Set `grafana_metrics_backend` to:

- **`prometheus`** (default) — in-cluster Prometheus is Grafana’s default datasource.
- **`mimir`** — Mimir is the default datasource; requires `enable_mimir = true` or `mimir_url`.

## Grafana login with Google

`grafana_google_auth` turns on Grafana's Google OAuth login. The client ID and
secret stay in a Secret that the caller creates in the monitoring namespace;
the module only references it (`GF_AUTH_GOOGLE_CLIENT_ID` /
`GF_AUTH_GOOGLE_CLIENT_SECRET` env vars), so they never appear in Helm values.

```hcl
resource "kubernetes_secret" "grafana_google_auth" {
  metadata {
    name      = "grafana-google-auth"
    namespace = module.monitoring.namespace # created by the module
  }
  data = {
    "client-id"     = var.google_client_id
    "client-secret" = var.google_client_secret
  }
}

module "monitoring" {
  # ...
  grafana_hostname = "grafana.c1.example.com"
  grafana_google_auth = {
    # Referencing the resource orders the Secret before the Helm release.
    existing_secret = kubernetes_secret.grafana_google_auth.metadata[0].name
    allowed_domains = ["example.com"]
  }
}
```

- Requires `grafana_hostname`: it becomes `root_url`, and the redirect URI to
  register in Google is `https://<grafana_hostname>/login/google`.
- Defaults: sign-up on, new users get `Viewer`, `skip_org_role_sync = true`
  (roles changed in Grafana stick), no auto-login. Override with
  `allow_sign_up`, `auto_assign_org_role`, `skip_org_role_sync`, `auto_login`,
  `hosted_domain`, `client_id_key`, `client_secret_key`.
- One apply on a fresh cluster: the `namespace` output comes from the
  module's namespace resource, so the Secret is created after the namespace
  and, through `existing_secret`, before the Helm release.

## Extra kube-prometheus-stack values

`kube_prometheus_stack_values` is passed to Helm as a second values document,
so Helm **deep-merges** it over the module defaults: maps merge key by key and
lists replace. For example, adding
`prometheus.prometheusSpec.additionalScrapeConfigs` keeps the module's
retention, storage and selectors.

## Dependencies

| Component | Depends on | Why |
|-----------|------------|-----|
| **kube-prometheus-stack** | monitoring namespace (+ remote_write auth secret when used) | Helm `create_namespace=false`; namespace managed in-module |
| **Grafana HTTPRoute** | kube-prometheus-stack + shared Gateway | Backend service must exist |
| **Mimir** | — | Independent Helm release in `mimir_namespace` |

For a public Grafana URL, the caller typically needs a **Gateway** (for example from
[`terraform-kubernetes-bootstrap`](https://github.com/HobOps/terraform-kubernetes-bootstrap))
with TLS and DNS before applying this module.

## Usage (Git source)

Until published to the Terraform Registry:

```hcl
module "monitoring" {
  source = "git::https://github.com/HobOps/terraform-kubernetes-monitoring.git?ref=v0.1.0"

  cluster_name = "acme-c1"

  grafana_metrics_backend = "prometheus"
  grafana_hostname        = "grafana.c1.example.com"
  gateway_name            = "public-gateway"
  gateway_namespace       = "infrastructure"

  prometheus_retention      = "15d"
  prometheus_retention_size = "20GB"
}
```

See [`examples/complete`](examples/complete) for a full thin wrapper (providers, backend).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3 |
| helm | >= 3.0, < 4 |
| kubernetes | >= 2.30, < 3 |
| kubectl | ~> 2.1 |
| random | >= 3.5, < 4 |

The **caller** must declare `random` in `required_providers` when using Terraform 0.13+ module provider passing rules (the module uses `random_password` for Grafana admin).

## Outputs

| Name | Description |
|------|-------------|
| `grafana_admin_password` | Admin password (sensitive; generated if not set) |
| `grafana_hostname` | Public hostname when HTTPRoute is enabled |
| `mimir_query_url` | In-cluster or external Mimir query URL when configured |
| `chart_versions` | Resolved Helm chart versions |

## Repository layout

```
.
├── *.tf                    # root module (Registry-compatible)
├── examples/complete/      # example caller stack
├── .github/workflows/ci.yml
├── .tflint.hcl
├── .checkov.yaml
├── commitlint.config.mjs
├── LICENSE
└── README.md
```

## CI / Versioning

`.github/workflows/ci.yml` calls the shared reusable workflow
[`HobOps/github-actions/.github/workflows/terraform-module-ci.yml`](https://github.com/HobOps/github-actions)
on pull requests to `main` and on pushes to `main`:

| Job | When | Purpose |
|-----|------|---------|
| `preflight` | PR | Branch name (`feat/*`, `fix/*`, `revert-*`) + conventional commits (commitlint) |
| `terraform-lint` | PR + push to main | `terraform fmt`, `validate` (root + examples), `tflint` |
| `security` | PR + push to main | Checkov scan of the Terraform |
| `release` | push to main | Compute next semver tag from conventional commits and publish a GitHub Release |

Make `ci / preflight`, `ci / terraform-lint`, and `ci / security` **required
status checks** on `main` so a feature branch must pass them before merge. You
can run the same pipeline on a feature branch by opening a PR against `main`.

Versioning is driven by [Conventional Commits](https://www.conventionalcommits.org/):
on merge to `main`, `feat:` bumps the minor, `fix:` the patch, and a
`BREAKING CHANGE:`/`!` the major. The resulting tag (`vX.Y.Z`) is what callers
pin with `?ref=`.
