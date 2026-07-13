resource "helm_release" "blackbox_exporter" {
  count = var.enable_blackbox_exporter ? 1 : 0

  name       = "prometheus-blackbox-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-blackbox-exporter"
  version    = local.chart_versions.blackbox_exporter
  namespace  = var.namespace
  timeout    = 300
  wait       = true

  values = [
    yamlencode(merge(
      {
        serviceMonitor = {
          selfMonitor = {
            enabled = true
            labels  = local.service_monitor_labels
          }
          enabled = length(var.blackbox_targets) > 0
          defaults = {
            labels = local.service_monitor_labels
            module = "http_2xx"
          }
          targets = [
            for t in var.blackbox_targets : {
              name   = t.name
              url    = t.url
              module = t.module
            }
          ]
        }
      },
      var.blackbox_exporter_values,
    ))
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "ipmi_exporter" {
  count = var.enable_ipmi_exporter ? 1 : 0

  name       = "prometheus-ipmi-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-ipmi-exporter"
  version    = local.chart_versions.ipmi_exporter
  namespace  = var.namespace
  timeout    = 300
  wait       = true

  values = [
    yamlencode(merge(
      {
        # Local BMC via OpenIPMI device on the node (/dev/ipmi0).
        modules = {
          default = {
            driver = "OPENIPMI"
            collectors = [
              "bmc",
              "ipmi",
              "chassis",
              "dcmi",
            ]
          }
        }
        # Image defaults to nobody; /dev/ipmi0 is root:root mode 0600, so the
        # process must run as root even with privileged=true.
        containerSecurityContext = {
          privileged   = true
          runAsUser    = 0
          runAsGroup   = 0
          runAsNonRoot = false
        }
        extraVolumes = [
          {
            name = "host-dev"
            hostPath = {
              path = "/dev"
            }
          },
        ]
        extraVolumeMounts = [
          {
            name      = "host-dev"
            mountPath = "/dev"
          },
        ]
        serviceMonitor = {
          enabled = true
          labels  = local.service_monitor_labels
        }
      },
      var.ipmi_exporter_values,
    ))
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "smartctl_exporter" {
  count = var.enable_smartctl_exporter ? 1 : 0

  name       = "prometheus-smartctl-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-smartctl-exporter"
  version    = local.chart_versions.smartctl_exporter
  namespace  = var.namespace
  timeout    = 300
  wait       = true

  values = [
    yamlencode(merge(
      {
        # Empty config → exporter auto-discovers devices (incl. MegaRAID / NVMe).
        # Override with smartctl_exporter_values.config if you need include/exclude.
        serviceMonitor = {
          enabled     = true
          extraLabels = local.service_monitor_labels
        }
        prometheusRules = {
          enabled     = true
          extraLabels = local.service_monitor_labels
        }
      },
      var.smartctl_exporter_values,
    ))
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}
