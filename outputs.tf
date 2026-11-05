output "cluster_name" {
  description = "Cluster name passed into the module."
  value       = var.cluster_name
}

output "namespace" {
  description = "Namespace where kube-prometheus-stack (and Grafana) run. Read from the namespace resource, so callers that create Secrets in it (e.g. for grafana_google_auth) are ordered after it."
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_metrics_backend" {
  description = "Grafana default metrics datasource mode (prometheus or mimir)."
  value       = var.grafana_metrics_backend
}

output "grafana_hostname" {
  description = "Public Grafana hostname when an HTTPRoute is configured."
  value       = var.grafana_hostname
}

output "grafana_admin_password" {
  description = "Grafana admin password when managed by this module (generated when grafana_admin_password is null). Null when the credentials come from a Secret."
  value       = local.grafana_admin_password
  sensitive   = true
}

output "grafana_admin_secret_name" {
  description = "Kubernetes Secret holding the Grafana admin credentials, if any (existing or materialized from Vault)."
  value       = local.grafana_admin_secret_name
}

output "grafana_google_auth_secret_name" {
  description = "Kubernetes Secret holding the Google OAuth client credentials, if any (existing or materialized from Vault)."
  value       = local.grafana_google_auth_secret_name
}

output "prometheus_retention" {
  description = "Local Prometheus TSDB retention duration."
  value       = var.prometheus_retention
}

output "mimir_enabled" {
  description = "Whether Grafana Mimir is installed in this cluster."
  value       = var.enable_mimir
}

output "mimir_query_url" {
  description = "Prometheus-compatible query URL used for Mimir datasources."
  value       = local.mimir_query_url
}

output "chart_versions" {
  description = "Resolved Helm chart versions."
  value       = local.chart_versions
}

output "otel_gateway_endpoint_grpc" {
  description = "In-cluster OTLP gRPC endpoint of the collector gateway (null when disabled)."
  value       = local.otel_collector_enabled ? local.otel_gateway_otlp_grpc : null
}

output "otel_gateway_endpoint_http" {
  description = "In-cluster OTLP HTTP endpoint of the collector gateway (null when disabled)."
  value       = local.otel_collector_enabled ? local.otel_gateway_otlp_http : null
}

output "otel_instrumentation_name" {
  description = "<namespace>/<name> to reference in instrumentation.opentelemetry.io/inject-* annotations (null when disabled)."
  value       = var.enable_otel_operator && var.enable_otel_instrumentation ? "${var.namespace}/${var.otel_instrumentation.name}" : null
}

output "loki_url" {
  description = "In-cluster Loki URL (null when disabled)."
  value       = local.loki_url
}

output "tempo_url" {
  description = "In-cluster Tempo URL (null when disabled)."
  value       = local.tempo_url
}
