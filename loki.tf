# Loki in monolithic mode: one StatefulSet with every component, enough for
# tens of GB/day. Chart from the maintained grafana-community repository (the
# grafana.github.io charts stopped receiving updates in January 2026). Chunks and index go to the object store in loki_storage
# (GCS, S3 or the PVC itself); the compactor enforces loki_retention_period.
# Ingestion is OTLP (http://loki.<ns>:3100/otlp) from the OTel gateway; nothing
# is exposed outside the cluster and multi-tenancy is off.
locals {
  loki_object_store = var.loki_storage.backend == "filesystem" ? "filesystem" : var.loki_storage.backend

  loki_storage_values = merge(
    {
      type = var.loki_storage.backend
    },
    var.loki_storage.backend == "filesystem" ? {} : {
      bucketNames = {
        chunks = var.loki_storage.bucket
        ruler  = var.loki_storage.bucket
        admin  = var.loki_storage.bucket
      }
    },
    var.loki_storage.backend == "s3" ? {
      s3 = {
        endpoint         = try(var.loki_storage.s3.endpoint, null)
        region           = try(var.loki_storage.s3.region, null)
        accessKeyId      = try(var.loki_s3_credentials.access_key_id, null)
        secretAccessKey  = try(var.loki_s3_credentials.secret_access_key, null)
        s3ForcePathStyle = try(var.loki_storage.s3.force_path_style, false)
        insecure         = try(var.loki_storage.s3.insecure, false)
      }
    } : {},
  )

  loki_values = {
    deploymentMode = "Monolithic"

    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = local.loki_storage_values
      schemaConfig = {
        configs = [
          {
            from         = "2024-04-01"
            store        = "tsdb"
            object_store = local.loki_object_store
            schema       = "v13"
            index = {
              prefix = "index_"
              period = "24h"
            }
          },
        ]
      }
      limits_config = {
        retention_period          = var.loki_retention_period
        allow_structured_metadata = true
        ingestion_rate_mb         = var.loki_ingestion_rate_mb
        ingestion_burst_size_mb   = var.loki_ingestion_rate_mb * 2
      }
      compactor = {
        retention_enabled    = true
        delete_request_store = local.loki_object_store
      }
      ingester = {
        chunk_encoding = "snappy"
      }
      analytics = {
        reporting_enabled = false
      }
    }

    singleBinary = {
      replicas  = 1
      resources = var.loki_resources
      persistence = {
        enabled = true
        size    = var.loki_storage_size
      }
    }
    # Simple-scalable components off (the chart defaults them to 3 replicas).
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }

    # No nginx in front: clients hit the loki Service directly.
    gateway = { enabled = false }
    # Memcached caches request 1 GiB / 8 GiB by default; not for this size.
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
    sidecar = {
      rules = { enabled = false }
    }

    serviceAccount = {
      create      = true
      name        = "loki"
      annotations = var.loki_service_account_annotations
    }

    monitoring = {
      serviceMonitor = {
        enabled = true
        labels  = local.service_monitor_labels
      }
    }
  }
}

resource "helm_release" "loki" {
  count = var.enable_loki ? 1 : 0

  name       = "loki"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "loki"
  version    = local.chart_versions.loki
  namespace  = var.namespace
  timeout    = 600
  wait       = true

  # Two documents so Helm deep-merges the caller's values over the defaults.
  values = [
    yamlencode(local.loki_values),
    yamlencode(var.loki_values),
  ]

  # ServiceMonitor CRD comes with kube-prometheus-stack.
  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.kube_prometheus_stack,
  ]

  lifecycle {
    precondition {
      condition     = var.loki_storage.backend == "filesystem" || var.loki_storage.bucket != null
      error_message = "loki_storage.bucket is required when loki_storage.backend is gcs or s3."
    }
  }
}
