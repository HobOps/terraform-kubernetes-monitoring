# Minimal Mimir install for a central metrics cluster. Uses the chart's
# bundled MinIO for object storage — replace with real S3/GCS via mimir_values
# before production load.
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

  values = [
    yamlencode(merge(
      {
        minio = {
          enabled = true
        }
        # Keep the default microservices topology; callers override via mimir_values.
      },
      var.mimir_values,
    ))
  ]
}
