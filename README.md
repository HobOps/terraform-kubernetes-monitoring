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
| `enable_mimir` | Grafana Mimir (long-term store; bundled MinIO by default, GCS/S3 with `mimir_storage`) |
| `enable_alloy` | Grafana Alloy as the scraper (ServiceMonitors/PodMonitors/Probes, PrometheusRules synced to the Mimir ruler, remote_write to Mimir) |
| `prometheus_enabled = false` | Turn off the kube-prometheus-stack Prometheus once Mimir stores everything (operator, CRDs, exporters, rules, Grafana and Alertmanager stay) |
| `enable_blackbox_exporter` | prometheus-blackbox-exporter (+ optional probe targets) |
| `enable_ipmi_exporter` | prometheus-ipmi-exporter (local OPENIPMI; privileged root + `/dev`) |
| `enable_smartctl_exporter` | prometheus-smartctl-exporter (DaemonSet; disk SMART) |
| `grafana_hostname` | Gateway API HTTPRoute to Grafana |
| `grafana_admin_existing_secret` | Grafana admin credentials from an existing Secret (instead of a password) |
| `grafana_admin_external_secret` | Grafana admin credentials from Vault via an ExternalSecret |
| `grafana_google_auth` | Grafana login with Google OAuth (credentials from an existing Secret or from Vault via an ExternalSecret) |
| `remote_write_url` | Prometheus remote_write to a central Mimir (or other backend) |
| `enable_otel_operator` / `enable_otel_collector` / `enable_otel_instrumentation` | OpenTelemetry Operator, Collector agent (logs) + gateway (OTLP), `Instrumentation` CR for auto-instrumentation |
| `enable_loki` | Grafana Loki single-binary (logs; GCS / S3 / PVC) |
| `enable_tempo` | Grafana Tempo monolithic (traces; metrics-generator → Prometheus) |

> **metrics-server:** not installed by this module. On k3s it usually ships in
> `kube-system`; elsewhere install it only if you need `kubectl top` / HPA.

## Grafana metrics backend

Set `grafana_metrics_backend` to:

- **`prometheus`** (default) — in-cluster Prometheus is Grafana’s default datasource.
- **`mimir`** — Mimir is the default datasource; requires `enable_mimir = true` or `mimir_url`.
  It gets the uid in `grafana_metrics_datasource_uid` (`prometheus` by default), the
  same one kube-prometheus-stack gives its Prometheus datasource, so existing
  dashboards keep working.

## Mimir as the single metrics store

For one cluster that keeps its own long-term metrics in object storage and no
longer stores anything in Prometheus:

```hcl
module "monitoring" {
  # ...
  enable_mimir               = true
  mimir_storage              = { backend = "gcs", bucket = "my-project-mimir" }
  mimir_single_replica       = true  # 1 replica per component, replication factor 1
  mimir_kafka_enabled        = false # classic architecture, no bundled Kafka
  mimir_multitenancy_enabled = false # single tenant: no X-Scope-OrgID anywhere
  mimir_retention_period     = "395d"

  enable_alloy            = true       # scrapes and syncs rules instead of Prometheus
  metrics_store           = "mimir"    # OTel gateway + Tempo metrics-generator -> Mimir
  grafana_metrics_backend = "mimir"    # Grafana datasource (uid "prometheus") -> Mimir
  prometheus_enabled      = false      # last step
}
```

- Grant the bucket to the `mimir` ServiceAccount of `mimir_namespace` (Workload
  Identity on GKE, no keys), or set `mimir_service_account_annotations`.
- OTLP ingestion keeps the Prometheus naming (`otel_metric_suffixes_enabled`: unit
  and `_total` suffixes) and promotes `prometheus_otlp_promote_resource_attributes`
  to labels, so names and labels match what the Prometheus OTLP receiver produced.
- The Mimir ruler evaluates the PrometheusRules (synced by Alloy) and sends alerts
  to the kube-prometheus-stack Alertmanager.
- Migrating from Prometheus without losing history: enable Mimir and Alloy first
  (both stores receive the same data while you compare), backfill the Prometheus
  TSDB blocks into Mimir (`mimirtool backfill`), switch `metrics_store` and
  `grafana_metrics_backend`, then set `prometheus_enabled = false`.
- Tempo's metrics-generator cannot send headers, so `metrics_store = "mimir"` with
  it enabled requires `mimir_multitenancy_enabled = false`.

## Grafana admin credentials

By default the module sets the admin password (`grafana_admin_password`, or a
random one exposed through the `grafana_admin_password` output). To keep the
credentials out of Terraform state, point the chart at a Secret instead:

- `grafana_admin_existing_secret`: a Secret the caller provisions in the
  monitoring namespace (keys `grafana_admin_user_key` /
  `grafana_admin_password_key`, default `username` / `password`).
- `grafana_admin_external_secret`: the module creates an **ExternalSecret**
  that materializes that Secret from Vault through a `ClusterSecretStore`
  (see [Grafana credentials from Vault](#grafana-credentials-from-vault-external-secrets)).

With either option `random_password` is not created and the
`grafana_admin_password` output is null; `grafana_admin_secret_name` tells
callers which Secret to read.

## Grafana login with Google

`grafana_google_auth` turns on Grafana's Google OAuth login. The client ID and
secret stay in a Secret in the monitoring namespace, either one the caller
creates (`existing_secret`) or one the module materializes from Vault
(`external_secret`); the module only references it (`GF_AUTH_GOOGLE_CLIENT_ID`
/ `GF_AUTH_GOOGLE_CLIENT_SECRET` env vars), so the values never appear in
Helm values.

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
- `enabled = false` keeps the block in place but turns the login off.

## Grafana credentials from Vault (External Secrets)

When the cluster runs the External Secrets Operator with a `ClusterSecretStore`
backed by Vault (for example from
[`terraform-kubernetes-bootstrap`](https://github.com/HobOps/terraform-kubernetes-bootstrap)),
the module can create the ExternalSecrets itself, so no credential ever goes
through Terraform variables or state:

```hcl
module "monitoring" {
  # ...
  grafana_hostname = "grafana.c1.example.com"

  # Vault key with `username` / `password` properties.
  grafana_admin_external_secret = {
    cluster_secret_store = "vault-infra"
    vault_key            = "grafana/credentials"
    secret_name          = "grafana-admin"
    refresh_interval     = "2m"
  }

  # Vault key with `client-id` / `client-secret` properties.
  grafana_google_auth = {
    external_secret = {
      cluster_secret_store = "vault-infra"
      vault_key            = "grafana/oidc-google"
      secret_name          = "grafana-auth-google"
      refresh_interval     = "2m"
    }
    allowed_domains = ["example.com"]
    hosted_domain   = "example.com"
  }
}
```

- The ExternalSecrets are created in the monitoring namespace and the Helm
  release waits for them to become `Ready`, so a missing Vault key fails the
  apply instead of starting Grafana with empty credentials.
- `grafana_admin_user_key` / `grafana_admin_password_key` name the properties
  read from the admin Vault key; the Google key is copied as a whole and read
  with `client_id_key` / `client_secret_key`.
- Whenever Grafana reads a Secret (existing or ExternalSecret), the Deployment
  gets the `secret.reloader.stakater.com/reload` annotation, so
  [Stakater Reloader](https://github.com/stakater/Reloader) restarts Grafana
  on rotation. Without Reloader the annotation is inert.

## OpenTelemetry, Loki and Tempo

Optional observability stack next to kube-prometheus-stack, all in `namespace`:

| Input | What it installs |
|-------|------------------|
| `enable_otel_operator` | OpenTelemetry Operator. Its admission webhooks take their certificate from **cert-manager**, which must already be installed |
| `enable_otel_collector` | `otel-agent` DaemonSet (every container log under `/var/log/pods`, tagged with namespace/pod/workload; kubelet stats optional) and `otel-gateway` Deployment (OTLP gRPC `4317` / HTTP `4318` for the apps). The gateway fans out traces → Tempo, logs → Loki, metrics → Prometheus OTLP receiver |
| `enable_otel_instrumentation` | `Instrumentation` CR (`<namespace>/default`) for Python, Node.js and Java auto-instrumentation, pointing at the gateway |
| `enable_loki` | Loki single-binary: OTLP ingestion, retention `loki_retention_period`, storage `loki_storage` |
| `enable_tempo` | Tempo monolithic: retention `tempo_retention`, storage `tempo_storage`, metrics-generator (RED span metrics + service graph) remote-written to Prometheus |

Prometheus gets `enableOTLPReceiver` when the collector is on and
`enableRemoteWriteReceiver` when Tempo's metrics-generator is on (override with
`prometheus_otlp_receiver_enabled` / `prometheus_remote_write_receiver_enabled`).
With `grafana_provision_otel_datasources` (default `true`) Grafana gets `Loki` and
`Tempo` datasources (uids `loki` / `tempo`) with trace ↔ log ↔ metric correlation:
`derivedFields` on `trace_id=<id>` in log lines, `tracesToLogsV2`, `serviceMap` and
`nodeGraph` on the metrics datasource (`grafana_metrics_datasource_uid`).

Example with GCS buckets through GKE Workload Identity (IAM granted straight to the
Kubernetes ServiceAccounts `<namespace>/loki` and `<namespace>/tempo`, no keys):

```hcl
  enable_otel_operator        = true
  enable_otel_collector       = true
  enable_otel_instrumentation = true

  enable_loki           = true
  loki_storage          = { backend = "gcs", bucket = "my-project-loki" }
  loki_retention_period = "720h" # 30 days

  enable_tempo    = true
  tempo_storage   = { backend = "gcs", bucket = "my-project-tempo" }
  tempo_retention = "336h" # 14 days
```

Loki and Tempo charts come from the maintained `grafana-community` repository
(the `grafana.github.io` ones are frozen since January 2026).

Storage backends: `filesystem` / `local` (PVC only, the default), `gcs` (Application
Default Credentials: Workload Identity on GKE, or a key mounted via `*_values`) and
`s3` (`loki_s3_credentials` / `tempo_s3_credentials`; MinIO works with
`force_path_style = true`). Retention is enforced by Loki and Tempo themselves: do
not add bucket lifecycle rules shorter than it.

To instrument a Deployment, annotate its pods and name the service; the image does
not change (the operator adds an init container that ships the agent):

```yaml
podAnnotations:
  instrumentation.opentelemetry.io/inject-python: "monitoring/default" # or inject-nodejs / inject-java
env:
  - name: OTEL_SERVICE_NAME
    value: my-service
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: deployment.environment=dev,service.namespace=my-app
```

The `Instrumentation` sets `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`,
`OTEL_LOGS_EXPORTER=none` (stdout logs are already shipped by the agent) and, for
Python, `OTEL_PYTHON_LOG_CORRELATION=true` so text logs carry `trace_id`/`span_id`.
Apps that speak OTLP themselves use the `otel_gateway_endpoint_*` outputs.

Sizing defaults are deliberately small (requests: agent 256Mi per node, gateway
512Mi, Loki 512Mi, Tempo 768Mi, operator 128Mi); tune with `otel_agent_resources`,
`otel_gateway_resources`, `loki_resources`, `tempo_resources`. Memcached caches,
the Loki canary and the nginx gateway are off.

## Extra kube-prometheus-stack values

`kube_prometheus_stack_values` is passed to Helm as a second values document,
so Helm **deep-merges** it over the module defaults: maps merge key by key and
lists replace. For example, adding
`prometheus.prometheusSpec.additionalScrapeConfigs` keeps the module's
retention, storage and selectors.

## Dependencies

| Component | Depends on | Why |
|-----------|------------|-----|
| **kube-prometheus-stack** | monitoring namespace (+ remote_write auth secret and Grafana ExternalSecrets when used) | Helm `create_namespace=false`; namespace managed in-module; Grafana must find its Secrets at start |
| **Grafana ExternalSecrets** | monitoring namespace + External Secrets Operator with the named `ClusterSecretStore` (caller) | Materialize admin / Google OAuth Secrets from Vault |
| **Grafana HTTPRoute** | kube-prometheus-stack + shared Gateway | Backend service must exist |
| **Mimir** | — | Independent Helm release in `mimir_namespace` |
| **OpenTelemetry Operator** | monitoring namespace + kube-prometheus-stack (ServiceMonitor CRD) + cert-manager (caller) | Webhook TLS certificate; self-monitoring |
| **OTel collectors / Instrumentation** | operator (CRDs), in-module RBAC, Loki / Tempo when enabled | Exporters target them |
| **Loki / Tempo** | monitoring namespace + kube-prometheus-stack (ServiceMonitor CRD; Prometheus is Tempo's remote-write target) | Object-storage credentials come from the platform identity or `*_s3_credentials` |

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
| `grafana_admin_password` | Admin password (sensitive; generated if not set; null when it lives in a Secret) |
| `grafana_admin_secret_name` | Secret with the admin credentials, when configured |
| `grafana_google_auth_secret_name` | Secret with the Google OAuth client credentials, when configured |
| `namespace` | Monitoring namespace (from the namespace resource) |
| `grafana_hostname` | Public hostname when HTTPRoute is enabled |
| `mimir_query_url` | In-cluster or external Mimir query URL when configured |
| `mimir_push_url` / `mimir_otlp_url` | In-cluster Mimir remote-write and OTLP/HTTP URLs (push falls back to `remote_write_url`) |
| `alloy_enabled` | Whether Grafana Alloy is the scraper |
| `chart_versions` | Resolved Helm chart versions |
| `otel_gateway_endpoint_grpc` / `otel_gateway_endpoint_http` | In-cluster OTLP endpoints of the collector gateway (null when disabled) |
| `otel_instrumentation_name` | `<namespace>/<name>` for the `inject-*` annotations (null when disabled) |
| `loki_url` / `tempo_url` | In-cluster query URLs (null when disabled) |

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
