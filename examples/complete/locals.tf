locals {
  kube_context = "example-c1"

  grafana_hostname          = "grafana.c1.example.com"
  grafana_metrics_backend   = "prometheus"
  gateway_name              = "public-gateway"
  gateway_namespace         = "infrastructure"

  enable_mimir = false

  prometheus_retention      = "15d"
  prometheus_retention_size = "20GB"

  chart_versions = {
    kube_prometheus_stack = "87.15.1"
    mimir_distributed     = "6.1.0"
  }
}
