resource "kubectl_manifest" "grafana_httproute" {
  count = var.grafana_hostname != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana"
      namespace = var.namespace
    }
    spec = {
      parentRefs = [
        {
          name        = var.gateway_name
          namespace   = var.gateway_namespace
          sectionName = "https"
        },
        {
          name        = var.gateway_name
          namespace   = var.gateway_namespace
          sectionName = "http"
        },
      ]
      hostnames = [
        var.grafana_hostname,
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            },
          ]
          backendRefs = [
            {
              name = local.grafana_service_name
              port = 80
            },
          ]
        },
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
