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

  # Two documents so Helm deep-merges the caller's values over the defaults.
  # A single merge() would replace whole top-level keys: passing
  # prometheus.prometheusSpec.additionalScrapeConfigs dropped the module's
  # retention, storageSpec and selectors.
  values = [
    yamlencode(local.kube_prometheus_stack_values),
    yamlencode(var.kube_prometheus_stack_values),
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
    precondition {
      condition     = var.grafana_google_auth == null || var.grafana_hostname != null
      error_message = "grafana_google_auth requires grafana_hostname (OAuth redirect URL)."
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
        basicAuth     = true
        basicAuthUser = var.mimir_basic_auth_username
        secureJsonData = merge(
          var.mimir_tenant_id != null ? { httpHeaderValue1 = var.mimir_tenant_id } : {},
          { basicAuthPassword = var.mimir_basic_auth_password },
        )
      } : {},
    )
  ]

  # Placeholder when OAuth is off, so attribute reads below never hit null.
  google_auth = var.grafana_google_auth != null ? var.grafana_google_auth : {
    existing_secret      = ""
    client_id_key        = ""
    client_secret_key    = ""
    allowed_domains      = []
    hosted_domain        = null
    auto_login           = false
    allow_sign_up        = false
    auto_assign_org_role = "Viewer"
    skip_org_role_sync   = true
  }

  # grafana.ini and env for Google OAuth. Credentials come from the caller's
  # Secret through GF_AUTH_GOOGLE_* env vars, never through values.
  # jsonencode/jsondecode: both branches of the conditional must share a type.
  grafana_google_auth_values = jsondecode(var.grafana_google_auth == null ? "{}" : jsonencode({
    "grafana.ini" = {
      server = {
        root_url = "https://${var.grafana_hostname}"
      }
      "auth.google" = merge(
        {
          enabled            = true
          scopes             = "openid email profile"
          allowed_domains    = join(" ", local.google_auth.allowed_domains)
          allow_sign_up      = local.google_auth.allow_sign_up
          auto_login         = local.google_auth.auto_login
          skip_org_role_sync = local.google_auth.skip_org_role_sync
        },
        local.google_auth.hosted_domain != null ? {
          hosted_domain = local.google_auth.hosted_domain
        } : {},
      )
      users = {
        auto_assign_org_role = local.google_auth.auto_assign_org_role
      }
    }
    envValueFrom = {
      GF_AUTH_GOOGLE_CLIENT_ID = {
        secretKeyRef = {
          name = local.google_auth.existing_secret
          key  = local.google_auth.client_id_key
        }
      }
      GF_AUTH_GOOGLE_CLIENT_SECRET = {
        secretKeyRef = {
          name = local.google_auth.existing_secret
          key  = local.google_auth.client_secret_key
        }
      }
    }
  }))

  kube_prometheus_stack_values = {
    fullnameOverride = local.release_name

    alertmanager = {
      enabled = var.enable_alertmanager
    }

    grafana = merge(local.grafana_google_auth_values, {
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
    })

    prometheus = {
      prometheusSpec = merge(
        {
          retention     = var.prometheus_retention
          retentionSize = var.prometheus_retention_size
          # Pick up ServiceMonitors / PodMonitors / Probes / Rules from sibling exporter charts.
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          probeSelectorNilUsesHelmValues          = false
          ruleSelectorNilUsesHelmValues           = false
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
