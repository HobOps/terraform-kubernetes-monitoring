# terraform-kubernetes-monitoring

Terraform module that installs cluster monitoring (kube-prometheus-stack, optional
Grafana Mimir, and an optional Grafana HTTPRoute). **kube-prometheus-stack is
always installed**; Mimir and the public Grafana route are optional.

Providers (`helm`, `kubernetes`, `kubectl`) are configured by the **caller**.

## Components

| Input | Component |
|-------|-----------|
| (always) | kube-prometheus-stack (Prometheus, Grafana, optional Alertmanager) |
| `enable_mimir` | Grafana Mimir (central long-term store; bundled MinIO by default) |
| `enable_blackbox_exporter` | prometheus-blackbox-exporter (+ optional probe targets) |
| `enable_ipmi_exporter` | prometheus-ipmi-exporter (local OPENIPMI; privileged `/dev`) |
| `enable_smartctl_exporter` | prometheus-smartctl-exporter (DaemonSet; disk SMART) |
| `grafana_hostname` | Gateway API HTTPRoute to Grafana |
| `remote_write_url` | Prometheus remote_write to a central Mimir (or other backend) |

> **metrics-server:** not installed by this module. On k3s it usually ships in
> `kube-system`; elsewhere install it only if you need `kubectl top` / HPA.

## Grafana metrics backend

Set `grafana_metrics_backend` to:

- **`prometheus`** (default) — in-cluster Prometheus is Grafana’s default datasource.
- **`mimir`** — Mimir is the default datasource; requires `enable_mimir = true` or `mimir_url`.

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
├── *.tf                 # root module (Registry-compatible)
├── examples/complete/   # example caller stack
├── LICENSE
└── README.md
```

## Versioning

Tag releases with semver (`v0.1.0`, `v1.0.0`, …) so callers can pin `?ref=`
and so the Terraform Registry can publish versions later.
