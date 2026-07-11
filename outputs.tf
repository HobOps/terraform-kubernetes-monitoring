output "cluster_name" {
  description = "Cluster name passed into the module."
  value       = var.cluster_name
}

output "namespace" {
  description = "Namespace where kube-prometheus-stack (and Grafana) run."
  value       = var.namespace
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
  description = "Grafana admin password (generated when grafana_admin_password is null)."
  value       = local.grafana_admin_password
  sensitive   = true
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
