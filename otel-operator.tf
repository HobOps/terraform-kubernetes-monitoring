# OpenTelemetry Operator: reconciles OpenTelemetryCollector and Instrumentation
# CRs and injects auto-instrumentation into annotated pods. Its admission
# webhooks get their TLS certificate from cert-manager, which the caller must
# already have installed (for example via terraform-kubernetes-bootstrap).
# The default collector image is the "k8s" distribution (filelog, k8sattributes,
# kubeletstats, otlp/otlphttp), which is what otel-collector.tf relies on.
resource "helm_release" "otel_operator" {
  count = var.enable_otel_operator ? 1 : 0

  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = local.chart_versions.opentelemetry_operator
  namespace  = var.namespace
  timeout    = 600
  wait       = true

  # Two documents so Helm deep-merges the caller's values over the defaults.
  values = [
    yamlencode({
      manager = {
        resources = var.otel_operator_resources
        serviceMonitor = {
          enabled     = true
          extraLabels = local.service_monitor_labels
        }
      }
      admissionWebhooks = {
        certManager = {
          enabled = true
        }
        autoGenerateCert = {
          enabled = false
        }
      }
    }),
    yamlencode(var.otel_operator_values),
  ]

  # ServiceMonitor CRD comes with kube-prometheus-stack.
  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.kube_prometheus_stack,
  ]
}
