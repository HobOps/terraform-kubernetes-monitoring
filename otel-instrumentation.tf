# Instrumentation CR: the operator injects the language agent (init container +
# env) into any pod annotated with
#   instrumentation.opentelemetry.io/inject-python|nodejs|java: "<namespace>/<name>"
# Telemetry goes to the gateway over OTLP/HTTP (4318), the protocol every
# auto-instrumentation supports. Logs stay on stdout: the agent DaemonSet ships
# them, so the SDK log exporter is off to avoid duplicates in Loki; Python gets
# trace_id/span_id appended to its text logs instead (OTEL_PYTHON_LOG_CORRELATION).
locals {
  otel_instrumentation_env = merge(
    {
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf"
      OTEL_LOGS_EXPORTER          = "none"
    },
    var.otel_instrumentation.env,
  )

  otel_instrumentation_python_env = merge(
    {
      OTEL_PYTHON_LOG_CORRELATION = "true"
    },
    var.otel_instrumentation.python_env,
  )
}

resource "kubectl_manifest" "otel_instrumentation" {
  count = var.enable_otel_operator && var.enable_otel_instrumentation ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "opentelemetry.io/v1alpha1"
    kind       = "Instrumentation"
    metadata = {
      name      = var.otel_instrumentation.name
      namespace = var.namespace
    }
    spec = {
      exporter = {
        endpoint = local.otel_gateway_otlp_http
      }
      propagators = var.otel_instrumentation.propagators
      sampler = {
        type     = var.otel_instrumentation.sampler_type
        argument = var.otel_instrumentation.sampler_argument
      }
      env = [for k, v in local.otel_instrumentation_env : { name = k, value = v }]
      python = {
        env = [for k, v in local.otel_instrumentation_python_env : { name = k, value = v }]
      }
      nodejs = {
        env = [for k, v in var.otel_instrumentation.nodejs_env : { name = k, value = v }]
      }
      java = {
        env = [for k, v in var.otel_instrumentation.java_env : { name = k, value = v }]
      }
    }
  })

  depends_on = [
    helm_release.otel_operator,
    kubectl_manifest.otel_gateway,
  ]

  lifecycle {
    precondition {
      condition     = local.otel_collector_enabled
      error_message = "enable_otel_instrumentation requires enable_otel_collector (the Instrumentation points at the gateway)."
    }
  }
}
