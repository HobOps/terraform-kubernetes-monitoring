# ExternalSecrets that materialize the Grafana admin and Google OAuth
# credential Secrets from Vault through a ClusterSecretStore. External Secrets
# Operator and the store are installed by the caller (e.g. the bootstrap
# module). The admin Secret maps the username/password properties explicitly;
# the Google OAuth Secret copies every property of the Vault key.

resource "kubectl_manifest" "grafana_admin_external_secret" {
  count = var.grafana_admin_external_secret != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.grafana_admin_external_secret.secret_name
      namespace = var.namespace
    }
    spec = {
      refreshInterval = var.grafana_admin_external_secret.refresh_interval
      secretStoreRef = {
        name = var.grafana_admin_external_secret.cluster_secret_store
        kind = "ClusterSecretStore"
      }
      target = {
        name           = var.grafana_admin_external_secret.secret_name
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = var.grafana_admin_user_key
          remoteRef = {
            key      = var.grafana_admin_external_secret.vault_key
            property = var.grafana_admin_user_key
          }
        },
        {
          secretKey = var.grafana_admin_password_key
          remoteRef = {
            key      = var.grafana_admin_external_secret.vault_key
            property = var.grafana_admin_password_key
          }
        },
      ]
    }
  })

  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "3m"
  }

  depends_on = [kubernetes_namespace.monitoring]
}

resource "kubectl_manifest" "grafana_google_auth_external_secret" {
  count = local.grafana_google_auth_enabled && try(var.grafana_google_auth.external_secret, null) != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.grafana_google_auth.external_secret.secret_name
      namespace = var.namespace
    }
    spec = {
      refreshInterval = var.grafana_google_auth.external_secret.refresh_interval
      secretStoreRef = {
        name = var.grafana_google_auth.external_secret.cluster_secret_store
        kind = "ClusterSecretStore"
      }
      target = {
        name           = var.grafana_google_auth.external_secret.secret_name
        creationPolicy = "Owner"
      }
      dataFrom = [
        {
          extract = {
            key = var.grafana_google_auth.external_secret.vault_key
          }
        },
      ]
    }
  })

  wait_for {
    condition {
      type   = "Ready"
      status = "True"
    }
  }

  timeouts {
    create = "3m"
  }

  depends_on = [kubernetes_namespace.monitoring]
}
