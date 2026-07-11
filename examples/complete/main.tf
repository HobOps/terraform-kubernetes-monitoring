module "monitoring" {
  source = "../.."

  cluster_name = local.kube_context

  grafana_metrics_backend = local.grafana_metrics_backend
  grafana_hostname        = local.grafana_hostname
  gateway_name            = local.gateway_name
  gateway_namespace       = local.gateway_namespace

  enable_mimir = local.enable_mimir

  prometheus_retention      = local.prometheus_retention
  prometheus_retention_size = local.prometheus_retention_size

  chart_versions = local.chart_versions
}
