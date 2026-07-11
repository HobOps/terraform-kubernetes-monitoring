resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret" "remote_write_auth" {
  count = var.remote_write_url != null && var.remote_write_basic_auth_username != null ? 1 : 0

  metadata {
    name      = "${local.release_name}-remote-write-auth"
    namespace = var.namespace
  }

  data = {
    username = var.remote_write_basic_auth_username
    password = var.remote_write_basic_auth_password
  }

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "kube_prometheus_stack" {
  name             = local.release_name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = local.chart_versions.kube_prometheus_stack
  namespace        = var.namespace
  create_namespace = false
  timeout          = 900
  wait             = true

  values = [
    yamlencode(merge(
      local.kube_prometheus_stack_values,
      var.kube_prometheus_stack_values,
    ))
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_secret.remote_write_auth,
  ]

  lifecycle {
    precondition {
      condition = (
        var.grafana_metrics_backend != "mimir" ||
        local.mimir_query_url != null
      )
      error_message = "grafana_metrics_backend=mimir requires enable_mimir=true or mimir_url."
    }
  }
}

locals {
  remote_write = var.remote_write_url == null ? [] : [
    merge(
      {
        url = var.remote_write_url
      },
      length(var.remote_write_headers) > 0 ? {
        headers = var.remote_write_headers
      } : {},
      var.remote_write_basic_auth_username != null ? {
        basicAuth = {
          username = {
            name = "${local.release_name}-remote-write-auth"
            key  = "username"
          }
          password = {
            name = "${local.release_name}-remote-write-auth"
            key  = "password"
          }
        }
      } : {},
    )
  ]

  grafana_mimir_datasource = var.grafana_metrics_backend != "mimir" ? [] : [
    merge(
      {
        name      = "Mimir"
        type      = "prometheus"
        url       = local.mimir_query_url
        access    = "proxy"
        isDefault = true
        jsonData = merge(
          {
            httpMethod     = "POST"
            prometheusType = "Mimir"
          },
          var.mimir_tenant_id != null ? {
            httpHeaderName1 = "X-Scope-OrgID"
          } : {},
        )
      },
      var.mimir_tenant_id != null ? {
        secureJsonData = {
          httpHeaderValue1 = var.mimir_tenant_id
        }
      } : {},
      var.mimir_basic_auth_username != null ? {
        basicAuth    = true
        basicAuthUser = var.mimir_basic_auth_username
        secureJsonData = merge(
          var.mimir_tenant_id != null ? { httpHeaderValue1 = var.mimir_tenant_id } : {},
          { basicAuthPassword = var.mimir_basic_auth_password },
        )
      } : {},
    )
  ]

  kube_prometheus_stack_values = {
    fullnameOverride = local.release_name

    alertmanager = {
      enabled = var.enable_alertmanager
    }

    grafana = {
      enabled       = true
      adminPassword = local.grafana_admin_password
      ingress = {
        enabled = false
      }
      persistence = {
        enabled = var.grafana_persistence_enabled
        size    = var.grafana_storage_size
      }
      forceDeployDatasources = var.grafana_metrics_backend == "mimir"
      sidecar = {
        datasources = {
          defaultDatasourceEnabled = var.grafana_metrics_backend == "prometheus"
        }
      }
      additionalDataSources = local.grafana_mimir_datasource
    }

    prometheus = {
      prometheusSpec = merge(
        {
          retention     = var.prometheus_retention
          retentionSize = var.prometheus_retention_size
          storageSpec = {
            volumeClaimTemplate = {
              spec = merge(
                {
                  accessModes = ["ReadWriteOnce"]
                  resources = {
                    requests = {
                      storage = var.prometheus_storage_size
                    }
                  }
                },
                var.prometheus_storage_class != null ? {
                  storageClassName = var.prometheus_storage_class
                } : {},
              )
            }
          }
          externalLabels = {
            cluster = var.cluster_name
          }
        },
        length(local.remote_write) > 0 ? {
          remoteWrite = local.remote_write
        } : {},
      )
    }
  }
}
