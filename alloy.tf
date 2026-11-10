# Grafana Alloy as the cluster scraper (replaces the kube-prometheus-stack
# Prometheus once Mimir stores everything):
#   - prometheus.operator.{servicemonitors,podmonitors,probes}: the same targets
#     the Prometheus Operator would hand to Prometheus.
#   - mimir.rules.kubernetes: syncs PrometheusRule objects (kube-prometheus-stack
#     defaults, exporters, apps) to the Mimir ruler, which evaluates them and
#     sends alerts to the kube-prometheus-stack Alertmanager.
#   - prometheus.remote_write: in-cluster Mimir (enable_mimir) or remote_write_url.
#
# One replica (Deployment) without clustering: every target is scraped once and
# the rules sync runs in a single place. ClusterIP only.

locals {
  alloy_remote_write_headers = merge(
    var.remote_write_headers,
    var.enable_mimir ? local.mimir_tenant_headers : {},
  )

  alloy_headers_river = length(local.alloy_remote_write_headers) == 0 ? "" : format(
    "    headers = {\n%s\n    }\n",
    # Alloy object literals need a trailing comma on every line.
    join("\n", [for k, v in local.alloy_remote_write_headers : format("      %q = %q,", k, v)]),
  )

  alloy_rules_river = !var.enable_mimir ? "" : format(<<-EOT
    mimir.rules.kubernetes "default" {
      address = %q
    %s}
    EOT
    , local.mimir_gateway_url,
    var.mimir_tenant_id != null ? format("  tenant_id = %q\n", var.mimir_tenant_id) : "",
  )

  alloy_config = <<-EOT
    prometheus.operator.servicemonitors "default" {
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.operator.podmonitors "default" {
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.operator.probes "default" {
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.remote_write "default" {
      endpoint {
        url = "${coalesce(local.mimir_push_url, "unset")}"
    ${local.alloy_headers_river}  }
      external_labels = {
        cluster = "${var.cluster_name}",
      }
    }

    ${local.alloy_rules_river}
  EOT

  alloy_values = {
    controller = {
      type     = "deployment"
      replicas = 1
    }
    alloy = {
      configMap = {
        content = local.alloy_config
      }
      clustering = {
        enabled = false
      }
      resources = var.alloy_resources
    }
  }
}

resource "helm_release" "alloy" {
  count = var.enable_alloy ? 1 : 0

  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = local.chart_versions.alloy
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600
  wait             = true

  # Two documents so Helm deep-merges the caller's values over the defaults.
  values = [
    yamlencode(local.alloy_values),
    yamlencode(var.alloy_values),
  ]

  # ServiceMonitor/PodMonitor/Probe/PrometheusRule CRDs come with
  # kube-prometheus-stack; the remote-write target is Mimir.
  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.mimir,
  ]

  lifecycle {
    precondition {
      condition     = local.mimir_push_url != null
      error_message = "enable_alloy needs a remote-write target: enable_mimir=true or remote_write_url."
    }
  }
}
