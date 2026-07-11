variable "cluster_name" {
  description = "Short cluster name (labels, external-dns ownership hints, etc.)."
  type        = string
}

variable "namespace" {
  description = "Namespace for kube-prometheus-stack (and Grafana)."
  type        = string
  default     = "monitoring"
}

variable "mimir_namespace" {
  description = "Namespace for Mimir when enable_mimir is true."
  type        = string
  default     = "mimir"
}

# --- Mode ---

variable "grafana_metrics_backend" {
  description = "Grafana default metrics datasource: prometheus (local) or mimir (central / long-term)."
  type        = string
  default     = "prometheus"

  validation {
    condition     = contains(["prometheus", "mimir"], var.grafana_metrics_backend)
    error_message = "grafana_metrics_backend must be \"prometheus\" or \"mimir\"."
  }
}

variable "enable_mimir" {
  description = "Install Grafana Mimir (central long-term store). Typically true only on the central cluster."
  type        = bool
  default     = false
}

variable "enable_alertmanager" {
  description = "Enable Alertmanager in kube-prometheus-stack."
  type        = bool
  default     = true
}

# --- Prometheus retention ---

variable "prometheus_retention" {
  description = "Local Prometheus TSDB retention duration (e.g. 15d)."
  type        = string
  default     = "15d"
}

variable "prometheus_retention_size" {
  description = "Local Prometheus TSDB size cap (e.g. 20GB). Empty string disables size-based retention."
  type        = string
  default     = "20GB"
}

variable "prometheus_storage_size" {
  description = "PVC size for Prometheus."
  type        = string
  default     = "20Gi"
}

variable "prometheus_storage_class" {
  description = "StorageClass for Prometheus PVC. null uses the cluster default."
  type        = string
  default     = null
}

# --- Grafana ---

variable "grafana_hostname" {
  description = "Public hostname for Grafana (HTTPRoute). null skips the HTTPRoute."
  type        = string
  default     = null
}

variable "grafana_admin_password" {
  description = "Grafana admin password. If null, a random password is generated and exposed via output."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_persistence_enabled" {
  description = "Enable PVC for Grafana."
  type        = bool
  default     = true
}

variable "grafana_storage_size" {
  description = "PVC size for Grafana when persistence is enabled."
  type        = string
  default     = "5Gi"
}

# --- Gateway (HTTPRoute) ---

variable "gateway_name" {
  description = "Shared Gateway name used by the Grafana HTTPRoute."
  type        = string
  default     = "public-gateway"
}

variable "gateway_namespace" {
  description = "Namespace of the shared Gateway."
  type        = string
  default     = "infrastructure"
}

# --- Mimir (when enable_mimir or external URL) ---

variable "mimir_url" {
  description = "Prometheus-compatible query URL for Mimir. When enable_mimir is true and this is null, the in-cluster nginx URL is used."
  type        = string
  default     = null
}

variable "mimir_tenant_id" {
  description = "X-Scope-OrgID tenant sent by Grafana when grafana_metrics_backend is mimir."
  type        = string
  default     = "anonymous"
}

variable "mimir_basic_auth_username" {
  description = "Optional basic-auth username for the Mimir Grafana datasource."
  type        = string
  default     = null
}

variable "mimir_basic_auth_password" {
  description = "Optional basic-auth password for the Mimir Grafana datasource."
  type        = string
  default     = null
  sensitive   = true
}

# --- Remote write (client → central Mimir) ---

variable "remote_write_url" {
  description = "Optional Prometheus remote_write URL (e.g. central Mimir push endpoint). null disables remote_write."
  type        = string
  default     = null
}

variable "remote_write_headers" {
  description = "Extra HTTP headers for remote_write (e.g. X-Scope-OrgID)."
  type        = map(string)
  default     = {}
}

variable "remote_write_basic_auth_username" {
  description = "Optional basic-auth username for remote_write."
  type        = string
  default     = null
}

variable "remote_write_basic_auth_password" {
  description = "Optional basic-auth password for remote_write."
  type        = string
  default     = null
  sensitive   = true
}

# --- Extra exporters (off by default) ---

variable "enable_blackbox_exporter" {
  description = "Install prometheus-blackbox-exporter (HTTP/TCP/ICMP probes)."
  type        = bool
  default     = false
}

variable "blackbox_targets" {
  description = "Blackbox probe targets (ServiceMonitors via the chart). Empty deploys the exporter only."
  type = list(object({
    name   = string
    url    = string
    module = optional(string, "http_2xx")
  }))
  default = []
}

variable "enable_ipmi_exporter" {
  description = "Install prometheus-ipmi-exporter (local OPENIPMI by default; needs host /dev access)."
  type        = bool
  default     = false
}

variable "enable_smartctl_exporter" {
  description = "Install prometheus-smartctl-exporter (DaemonSet; privileged host /dev access)."
  type        = bool
  default     = false
}

variable "blackbox_exporter_values" {
  description = "Extra values merged on top of module defaults for blackbox-exporter."
  type        = any
  default     = {}
}

variable "ipmi_exporter_values" {
  description = "Extra values merged on top of module defaults for ipmi-exporter."
  type        = any
  default     = {}
}

variable "smartctl_exporter_values" {
  description = "Extra values merged on top of module defaults for smartctl-exporter."
  type        = any
  default     = {}
}

# --- Chart versions / overrides ---

variable "chart_versions" {
  description = "Helm chart versions. Omitted keys use module defaults."
  type = object({
    kube_prometheus_stack   = optional(string)
    mimir_distributed       = optional(string)
    blackbox_exporter       = optional(string)
    ipmi_exporter           = optional(string)
    smartctl_exporter       = optional(string)
  })
  default = {}
}

variable "kube_prometheus_stack_values" {
  description = "Extra values merged on top of the module defaults for kube-prometheus-stack (deep merge is caller's responsibility; this replaces keys at the top level of the encoded map via merge)."
  type        = any
  default     = {}
}

variable "mimir_values" {
  description = "Extra values merged on top of the module defaults for mimir-distributed."
  type        = any
  default     = {}
}

locals {
  chart_versions = {
    kube_prometheus_stack = coalesce(try(var.chart_versions.kube_prometheus_stack, null), "87.15.1")
    mimir_distributed     = coalesce(try(var.chart_versions.mimir_distributed, null), "6.1.0")
    blackbox_exporter     = coalesce(try(var.chart_versions.blackbox_exporter, null), "11.15.1")
    ipmi_exporter         = coalesce(try(var.chart_versions.ipmi_exporter, null), "0.8.0")
    smartctl_exporter     = coalesce(try(var.chart_versions.smartctl_exporter, null), "0.17.1")
  }

  grafana_admin_password = coalesce(var.grafana_admin_password, random_password.grafana_admin.result)

  mimir_query_url = var.mimir_url != null ? var.mimir_url : (
    var.enable_mimir ? "http://mimir-nginx.${var.mimir_namespace}.svc.cluster.local/prometheus" : null
  )

  release_name         = "kube-prometheus-stack"
  grafana_service_name = "${local.release_name}-grafana"

  # Shared label so Prometheus Operator (when using Helm selectors) still finds exporters.
  service_monitor_labels = {
    release = local.release_name
  }
}
