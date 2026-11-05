# Tempo 3 monolithic (live-store + backend worker in one process): receives OTLP
# from the OTel gateway, stores blocks in tempo_storage (GCS, S3 or the PVC) and
# keeps them for tempo_retention. Chart from the maintained grafana-community
# repository. The metrics-generator derives RED metrics per service
# (span-metrics) and the service graph, and remote-writes them to the
# in-cluster Prometheus (which needs enableRemoteWriteReceiver, see
# kube-prometheus-stack.tf). ClusterIP only.
locals {
  tempo_trace_storage = merge(
    {
      backend = var.tempo_storage.backend
      wal = {
        path = "/var/tempo/wal"
      }
    },
    var.tempo_storage.backend == "gcs" ? {
      gcs = {
        bucket_name = var.tempo_storage.bucket
      }
    } : {},
    var.tempo_storage.backend == "s3" ? {
      s3 = {
        bucket         = var.tempo_storage.bucket
        endpoint       = try(var.tempo_storage.s3.endpoint, null)
        region         = try(var.tempo_storage.s3.region, null)
        access_key     = try(var.tempo_s3_credentials.access_key_id, null)
        secret_key     = try(var.tempo_s3_credentials.secret_access_key, null)
        forcepathstyle = try(var.tempo_storage.s3.force_path_style, false)
        insecure       = try(var.tempo_storage.s3.insecure, false)
      }
    } : {},
  )

  tempo_values = {
    tempo = {
      resources        = var.tempo_resources
      reportingEnabled = false
      # Chart >= 3.2 renders this into backend_worker/backend_scheduler compaction.
      retention = var.tempo_retention

      storage = {
        trace = local.tempo_trace_storage
      }

      # Receivers stay at the chart defaults (OTLP 4317/4318 plus Jaeger and
      # OpenCensus ports): the templates dereference the Jaeger block, so it
      # cannot be removed. Only OTLP is used; the Service is ClusterIP.

      metricsGenerator = {
        enabled        = var.tempo_metrics_generator_enabled
        remoteWriteUrl = "${local.prometheus_url}/api/v1/write"
      }
      overrides = {
        defaults = var.tempo_metrics_generator_enabled ? {
          metrics_generator = {
            processors = ["service-graphs", "span-metrics"]
          }
        } : {}
      }
    }

    persistence = {
      enabled = true
      size    = var.tempo_storage_size
    }

    serviceAccount = {
      create      = true
      name        = "tempo"
      annotations = var.tempo_service_account_annotations
    }

    serviceMonitor = {
      enabled          = true
      additionalLabels = local.service_monitor_labels
    }
  }
}

resource "helm_release" "tempo" {
  count = var.enable_tempo ? 1 : 0

  name       = "tempo"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "tempo"
  version    = local.chart_versions.tempo
  namespace  = var.namespace
  timeout    = 600
  wait       = true

  # Two documents so Helm deep-merges the caller's values over the defaults.
  values = [
    yamlencode(local.tempo_values),
    yamlencode(var.tempo_values),
  ]

  # ServiceMonitor CRD and the remote-write target come with kube-prometheus-stack.
  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.kube_prometheus_stack,
  ]

  lifecycle {
    precondition {
      condition     = var.tempo_storage.backend == "local" || var.tempo_storage.bucket != null
      error_message = "tempo_storage.bucket is required when tempo_storage.backend is gcs or s3."
    }
    precondition {
      condition     = !var.tempo_metrics_generator_enabled || local.prometheus_remote_write_receiver_enabled
      error_message = "tempo_metrics_generator_enabled needs the Prometheus remote-write receiver (prometheus_remote_write_receiver_enabled)."
    }
  }
}
