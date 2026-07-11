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

  enable_blackbox_exporter = local.enable_blackbox_exporter
  enable_ipmi_exporter     = local.enable_ipmi_exporter
  enable_smartctl_exporter = local.enable_smartctl_exporter
  blackbox_targets         = local.blackbox_targets

  chart_versions = local.chart_versions
}
