# Grafana Mimir (mimir-distributed). Two shapes:
#
# - Default (backwards compatible): the chart's own topology with the bundled
#   MinIO and the ingest-storage (Kafka) architecture. Fine for a demo or a
#   central cluster sized through mimir_values.
# - Single cluster, long-term store (mimir_storage.backend = "gcs"/"s3",
#   mimir_single_replica = true, mimir_kafka_enabled = false): object storage,
#   classic architecture (distributor -> ingester over gRPC, no Kafka), one
#   replica per component, no zone awareness, replication factor 1.
#
# OTLP ingestion keeps the Prometheus naming (unit/_total suffixes) and promotes
# the same resource attributes as the Prometheus OTLP receiver, so dashboards
# built on Prometheus keep working against Mimir.

locals {
  mimir_object_storage = contains(["gcs", "s3"], var.mimir_storage.backend)

  # jsonencode/jsondecode: the branches of each conditional have different shapes.
  mimir_storage_config = jsondecode(
    var.mimir_storage.backend == "gcs" ? jsonencode({
      backend = "gcs"
      gcs     = { bucket_name = var.mimir_storage.bucket }
    }) :
    var.mimir_storage.backend == "s3" ? jsonencode({
      backend = "s3"
      s3 = merge(
        { bucket_name = var.mimir_storage.bucket },
        var.mimir_storage.endpoint != null ? { endpoint = var.mimir_storage.endpoint } : {},
        var.mimir_storage.region != null ? { region = var.mimir_storage.region } : {},
      )
    }) : "null"
  )

  mimir_structured_config = merge(
    {
      multitenancy_enabled = var.mimir_multitenancy_enabled
      limits = merge(
        {
          otel_metric_suffixes_enabled     = true
          promote_otel_resource_attributes = join(",", var.prometheus_otlp_promote_resource_attributes)
        },
        var.mimir_retention_period != null ? {
          compactor_blocks_retention_period = var.mimir_retention_period
        } : {},
      )
    },
    jsondecode(!local.mimir_object_storage ? "{}" : jsonencode({
      common               = { storage = local.mimir_storage_config }
      blocks_storage       = { storage_prefix = "blocks" }
      ruler_storage        = { storage_prefix = "ruler" }
      alertmanager_storage = { storage_prefix = "alertmanager" }
    })),
    jsondecode(var.mimir_kafka_enabled ? "{}" : jsonencode({
      ingest_storage = { enabled = false }
    })),
    # ingester: replication factor 1 for a single replica; gRPC push without Kafka.
    jsondecode(!(var.mimir_single_replica || !var.mimir_kafka_enabled) ? "{}" : jsonencode({
      ingester = merge(
        var.mimir_single_replica ? { ring = { replication_factor = 1 } } : {},
        var.mimir_kafka_enabled ? {} : { push_grpc_method_enabled = true },
      )
    })),
    jsondecode(!var.enable_alertmanager ? "{}" : jsonencode({
      ruler = {
        alertmanager_url = "http://${local.release_name}-alertmanager.${var.namespace}.svc.cluster.local:9093"
      }
    })),
  )

  mimir_single_replica_values = jsondecode(!var.mimir_single_replica ? "{}" : jsonencode({
    ingester = {
      replicas             = 1
      zoneAwareReplication = { enabled = false }
    }
    store_gateway = {
      replicas             = 1
      zoneAwareReplication = { enabled = false }
    }
    distributor    = { replicas = 1 }
    querier        = { replicas = 1 }
    query_frontend = { replicas = 1 }
    compactor      = { replicas = 1 }
    ruler          = { replicas = 1 }
    # Mimir's own alertmanager is not used: the ruler sends to the
    # kube-prometheus-stack Alertmanager.
    alertmanager = { enabled = false }
    # query-scheduler only pays off with several query-frontends.
    query_scheduler    = { enabled = false }
    overrides_exporter = { enabled = false }
    # Only needed to roll zone-aware StatefulSets.
    rollout_operator = { enabled = false }
  }))

  mimir_values = merge(
    {
      minio = { enabled = !local.mimir_object_storage }
      kafka = { enabled = var.mimir_kafka_enabled }
      mimir = { structuredConfig = local.mimir_structured_config }
    },
    jsondecode(length(var.mimir_service_account_annotations) == 0 ? "{}" : jsonencode({
      serviceAccount = { annotations = var.mimir_service_account_annotations }
    })),
    local.mimir_single_replica_values,
  )
}

resource "helm_release" "mimir" {
  count = var.enable_mimir ? 1 : 0

  name             = "mimir"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "mimir-distributed"
  version          = local.chart_versions.mimir_distributed
  namespace        = var.mimir_namespace
  create_namespace = true
  timeout          = 900
  wait             = true

  # Two documents so Helm deep-merges the caller's values over the defaults.
  values = [
    yamlencode(local.mimir_values),
    yamlencode(var.mimir_values),
  ]

  lifecycle {
    precondition {
      condition     = !local.mimir_object_storage || var.mimir_storage.bucket != null
      error_message = "mimir_storage.bucket is required when mimir_storage.backend is gcs or s3."
    }
  }
}
