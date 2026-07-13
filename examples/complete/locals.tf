locals {
  kube_context = "example-c1"

  grafana_hostname        = "grafana.c1.example.com"
  grafana_metrics_backend = "prometheus"
  gateway_name            = "public-gateway"
  gateway_namespace       = "infrastructure"

  enable_mimir = false

  prometheus_retention      = "15d"
  prometheus_retention_size = "20GB"

  enable_blackbox_exporter = false
  enable_ipmi_exporter     = false
  enable_smartctl_exporter = false
  blackbox_targets         = []

  chart_versions = {
    kube_prometheus_stack = "87.15.1"
    mimir_distributed     = "6.1.0"
    blackbox_exporter     = "11.15.1"
    ipmi_exporter         = "0.8.0"
    smartctl_exporter     = "0.17.1"
  }
}
