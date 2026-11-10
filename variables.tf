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
  description = "Install Grafana Mimir (long-term metrics store). See mimir_storage, mimir_single_replica and mimir_kafka_enabled for a single-cluster install."
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
  description = "Grafana admin password. Ignored when the admin credentials come from a Secret (grafana_admin_existing_secret / grafana_admin_external_secret). If null, a random password is generated and exposed via output."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_admin_existing_secret" {
  description = "Name of an existing Kubernetes Secret in the monitoring namespace with the Grafana admin credentials (chart admin.existingSecret). The caller provisions it; keys are grafana_admin_user_key / grafana_admin_password_key."
  type        = string
  default     = null
}

variable "grafana_admin_external_secret" {
  description = <<-EOT
    Create an ExternalSecret that materializes the Grafana admin credentials
    Secret from Vault through a ClusterSecretStore (External Secrets Operator
    must already be installed). Takes precedence over
    grafana_admin_existing_secret and grafana_admin_password. The Vault key
    must expose the username/password under grafana_admin_user_key /
    grafana_admin_password_key. null disables it.
  EOT
  type = object({
    cluster_secret_store = string
    vault_key            = string
    secret_name          = string
    refresh_interval     = optional(string, "1h")
  })
  default = null
}

variable "grafana_admin_user_key" {
  description = "Key in the Grafana admin Secret that holds the admin username."
  type        = string
  default     = "username"
}

variable "grafana_admin_password_key" {
  description = "Key in the Grafana admin Secret that holds the admin password."
  type        = string
  default     = "password"
}

variable "grafana_google_auth" {
  description = <<-EOT
    Google OAuth login for Grafana. null disables it. The client ID and secret
    come from a Kubernetes Secret in the monitoring namespace (keys
    client_id_key / client_secret_key): either existing_secret (a Secret the
    caller provisions) or external_secret (an ExternalSecret this module
    creates from Vault through a ClusterSecretStore). The module never sees
    the values. Requires grafana_hostname (used as root_url for the OAuth
    redirect: https://<grafana_hostname>/login/google).
  EOT
  type = object({
    enabled         = optional(bool, true)
    existing_secret = optional(string)
    external_secret = optional(object({
      cluster_secret_store = string
      vault_key            = string
      secret_name          = string
      refresh_interval     = optional(string, "1h")
    }))
    client_id_key        = optional(string, "client-id")
    client_secret_key    = optional(string, "client-secret")
    allowed_domains      = optional(list(string), [])
    hosted_domain        = optional(string)
    auto_login           = optional(bool, false)
    allow_sign_up        = optional(bool, true)
    auto_assign_org_role = optional(string, "Viewer")
    skip_org_role_sync   = optional(bool, true)
  })
  default = null

  validation {
    condition = var.grafana_google_auth == null || contains(
      ["Viewer", "Editor", "Admin"],
      try(var.grafana_google_auth.auto_assign_org_role, "Viewer"),
    )
    error_message = "grafana_google_auth.auto_assign_org_role must be Viewer, Editor or Admin."
  }

  validation {
    condition = (
      var.grafana_google_auth == null ||
      !try(var.grafana_google_auth.enabled, true) ||
      try(var.grafana_google_auth.external_secret, null) != null ||
      try(var.grafana_google_auth.existing_secret, null) != null
    )
    error_message = "grafana_google_auth needs existing_secret or external_secret when enabled."
  }
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
    kube_prometheus_stack  = optional(string)
    mimir_distributed      = optional(string)
    blackbox_exporter      = optional(string)
    ipmi_exporter          = optional(string)
    smartctl_exporter      = optional(string)
    opentelemetry_operator = optional(string)
    loki                   = optional(string)
    tempo                  = optional(string)
    alloy                  = optional(string)
  })
  default = {}
}

variable "kube_prometheus_stack_values" {
  description = "Extra values for kube-prometheus-stack, deep-merged by Helm on top of the module defaults (maps merge key by key; lists replace)."
  type        = any
  default     = {}
}

variable "mimir_values" {
  description = "Extra values for mimir-distributed, deep-merged by Helm on top of the module defaults."
  type        = any
  default     = {}
}

variable "mimir_storage" {
  description = "Mimir object storage. backend: minio (bundled MinIO, default), gcs or s3. bucket is required for gcs/s3; endpoint/region only for s3. With gcs, grant the bucket to the mimir ServiceAccount through Workload Identity (no keys)."
  type = object({
    backend  = optional(string, "minio")
    bucket   = optional(string)
    endpoint = optional(string)
    region   = optional(string)
  })
  default = {}

  validation {
    condition     = contains(["minio", "gcs", "s3"], var.mimir_storage.backend)
    error_message = "mimir_storage.backend must be minio, gcs or s3."
  }
}

variable "mimir_kafka_enabled" {
  description = "Use Mimir's ingest-storage architecture (bundled Kafka, chart default). false = classic architecture: distributors push to ingesters over gRPC, no Kafka (saves ~1 CPU / 1 GiB for a small single-cluster install)."
  type        = bool
  default     = true
}

variable "mimir_multitenancy_enabled" {
  description = "Require the X-Scope-OrgID header on writes and reads (Mimir default). false = single tenant 'anonymous': Alloy, the OTel gateway, Tempo's metrics-generator and Grafana need no header."
  type        = bool
  default     = true
}

variable "mimir_single_replica" {
  description = "Run one replica per Mimir component, without zone-aware replication and with replication factor 1 (single cluster, low volume). Also disables Mimir's alertmanager, query-scheduler, overrides-exporter and rollout-operator."
  type        = bool
  default     = false
}

variable "mimir_retention_period" {
  description = "Blocks retention enforced by Mimir's compactor (e.g. \"395d\"). null keeps blocks forever (Mimir default)."
  type        = string
  default     = null
}

variable "mimir_service_account_annotations" {
  description = "Annotations for the mimir ServiceAccount (e.g. iam.gke.io/gcp-service-account when using a GSA instead of direct Workload Identity)."
  type        = map(string)
  default     = {}
}

# --- Metrics pipeline (where metrics are stored and who scrapes) ---

variable "metrics_store" {
  description = "Where the OTel gateway (OTLP from apps) and Tempo's metrics-generator send metrics: prometheus (in-cluster Prometheus receivers) or mimir (in-cluster Mimir, requires enable_mimir)."
  type        = string
  default     = "prometheus"

  validation {
    condition     = contains(["prometheus", "mimir"], var.metrics_store)
    error_message = "metrics_store must be \"prometheus\" or \"mimir\"."
  }
}

variable "prometheus_enabled" {
  description = "Run the kube-prometheus-stack Prometheus. Set false once Grafana Alloy scrapes and Mimir stores everything: the operator, its CRDs, exporters, rules, Grafana and Alertmanager stay."
  type        = bool
  default     = true
}

variable "enable_alloy" {
  description = "Install Grafana Alloy as the scraper: discovers the ServiceMonitors/PodMonitors/Probes Prometheus would scrape, syncs PrometheusRules to the Mimir ruler and remote-writes to Mimir (in-cluster when enable_mimir, otherwise remote_write_url)."
  type        = bool
  default     = false
}

variable "alloy_resources" {
  description = "Requests/limits for the Alloy container."
  type = object({
    requests = optional(map(string), { cpu = "100m", memory = "384Mi" })
    limits   = optional(map(string), { cpu = "1", memory = "1Gi" })
  })
  default = {}
}

variable "alloy_values" {
  description = "Extra values for the alloy chart, deep-merged by Helm on top of the module defaults."
  type        = any
  default     = {}
}

locals {
  chart_versions = {
    kube_prometheus_stack  = coalesce(try(var.chart_versions.kube_prometheus_stack, null), "87.15.1")
    mimir_distributed      = coalesce(try(var.chart_versions.mimir_distributed, null), "6.1.0")
    blackbox_exporter      = coalesce(try(var.chart_versions.blackbox_exporter, null), "11.15.1")
    ipmi_exporter          = coalesce(try(var.chart_versions.ipmi_exporter, null), "0.8.0")
    smartctl_exporter      = coalesce(try(var.chart_versions.smartctl_exporter, null), "0.17.1")
    opentelemetry_operator = coalesce(try(var.chart_versions.opentelemetry_operator, null), "0.129.0")
    loki                   = coalesce(try(var.chart_versions.loki, null), "21.0.0")
    tempo                  = coalesce(try(var.chart_versions.tempo, null), "3.2.1")
    alloy                  = coalesce(try(var.chart_versions.alloy, null), "1.15.0")
  }

  # Grafana admin credentials: ExternalSecret > existing Secret > explicit password > random.
  grafana_admin_from_secret = var.grafana_admin_external_secret != null || var.grafana_admin_existing_secret != null

  grafana_admin_secret_name = (
    var.grafana_admin_external_secret != null
    ? var.grafana_admin_external_secret.secret_name
    : var.grafana_admin_existing_secret
  )

  grafana_admin_password = local.grafana_admin_from_secret ? null : coalesce(
    var.grafana_admin_password,
    try(random_password.grafana_admin[0].result, null),
  )

  grafana_google_auth_enabled = var.grafana_google_auth != null && try(var.grafana_google_auth.enabled, true)

  grafana_google_auth_secret_name = local.grafana_google_auth_enabled ? try(coalesce(
    try(var.grafana_google_auth.external_secret.secret_name, null),
    try(var.grafana_google_auth.existing_secret, null),
  ), null) : null

  # Secrets Grafana reads at start-up. Stakater Reloader, when installed,
  # restarts the pod on rotation (annotation on the Grafana Deployment).
  grafana_reloader_secrets = [
    for name in [local.grafana_admin_secret_name, local.grafana_google_auth_secret_name] : name
    if name != null
  ]

  # mimir-distributed >= 5 fronts every component with "mimir-gateway" (it used
  # to be "mimir-nginx").
  mimir_gateway_url = var.enable_mimir ? "http://mimir-gateway.${var.mimir_namespace}.svc.cluster.local" : null
  mimir_query_url = var.mimir_url != null ? var.mimir_url : (
    var.enable_mimir ? "${local.mimir_gateway_url}/prometheus" : null
  )
  # remote_write target for Alloy and Tempo: the in-cluster Mimir, else remote_write_url.
  mimir_push_url = var.enable_mimir ? "${local.mimir_gateway_url}/api/v1/push" : var.remote_write_url
  # OTLP/HTTP base for the OTel gateway (the exporter appends /v1/metrics).
  mimir_otlp_url = var.enable_mimir ? "${local.mimir_gateway_url}/otlp" : null
  # Tenant header for writes; harmless when multitenancy is off.
  mimir_tenant_headers = var.mimir_tenant_id != null ? { "X-Scope-OrgID" = var.mimir_tenant_id } : {}

  release_name         = "kube-prometheus-stack"
  grafana_service_name = "${local.release_name}-grafana"

  # Shared label so Prometheus Operator (when using Helm selectors) still finds exporters.
  service_monitor_labels = {
    release = local.release_name
  }
}

# --- OpenTelemetry (operator, collectors, instrumentation) ---

variable "enable_otel_operator" {
  description = "Install the OpenTelemetry Operator (reconciles OpenTelemetryCollector / Instrumentation CRs). Its webhooks need cert-manager in the cluster."
  type        = bool
  default     = false
}

variable "otel_operator_resources" {
  description = "Requests/limits for the operator manager container."
  type = object({
    requests = optional(map(string), { cpu = "50m", memory = "128Mi" })
    limits   = optional(map(string), { cpu = "500m", memory = "256Mi" })
  })
  default = {}
}

variable "otel_operator_values" {
  description = "Extra values for opentelemetry-operator, deep-merged by Helm on top of the module defaults."
  type        = any
  default     = {}
}

variable "enable_otel_collector" {
  description = "Create the OTel Collector agent (DaemonSet: container logs) and gateway (Deployment: OTLP 4317/4318 for apps). Requires enable_otel_operator and at least one backend (Loki, Tempo or the Prometheus OTLP receiver)."
  type        = bool
  default     = false
}

variable "otel_agent_kubeletstats_enabled" {
  description = "Also scrape kubelet pod/container/node stats from the agent and ship them to Prometheus over OTLP. Off by default: kube-prometheus-stack already scrapes cAdvisor, so this mostly duplicates series."
  type        = bool
  default     = false
}

variable "otel_agent_log_exclude" {
  description = "Extra /var/log/pods globs the agent skips (the collectors' own logs are always skipped)."
  type        = list(string)
  default     = []
}

variable "otel_agent_resources" {
  description = "Requests/limits for each agent pod (one per node)."
  type = object({
    requests = optional(map(string), { cpu = "100m", memory = "256Mi" })
    limits   = optional(map(string), { cpu = "500m", memory = "512Mi" })
  })
  default = {}
}

variable "otel_gateway_replicas" {
  description = "Gateway replicas."
  type        = number
  default     = 1
}

variable "otel_gateway_resources" {
  description = "Requests/limits for each gateway pod."
  type = object({
    requests = optional(map(string), { cpu = "200m", memory = "512Mi" })
    limits   = optional(map(string), { cpu = "1", memory = "1Gi" })
  })
  default = {}
}

variable "enable_otel_instrumentation" {
  description = "Create the Instrumentation CR the apps reference with instrumentation.opentelemetry.io/inject-<lang>: \"<namespace>/<name>\". Requires enable_otel_collector."
  type        = bool
  default     = false
}

variable "otel_instrumentation" {
  description = "Instrumentation CR settings. env applies to every language; *_env to one. The module always sets OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf, OTEL_LOGS_EXPORTER=none and, for Python, OTEL_PYTHON_LOG_CORRELATION=true (override them here)."
  type = object({
    name             = optional(string, "default")
    sampler_type     = optional(string, "parentbased_traceidratio")
    sampler_argument = optional(string, "1.0")
    propagators      = optional(list(string), ["tracecontext", "baggage"])
    env              = optional(map(string), {})
    python_env       = optional(map(string), {})
    nodejs_env       = optional(map(string), {})
    java_env         = optional(map(string), {})
  })
  default = {}
}

# --- Loki ---

variable "enable_loki" {
  description = "Install Loki (single-binary) in the monitoring namespace."
  type        = bool
  default     = false
}

variable "loki_storage" {
  description = "Where Loki keeps chunks and index: filesystem (PVC only), gcs or s3 (bucket required). GCS auth is ADC (GKE Workload Identity bound to the ServiceAccount <namespace>/loki, or a mounted key via loki_values). S3 keys go in loki_s3_credentials."
  type = object({
    backend = optional(string, "filesystem")
    bucket  = optional(string)
    s3 = optional(object({
      endpoint         = optional(string)
      region           = optional(string)
      force_path_style = optional(bool, false)
      insecure         = optional(bool, false)
    }))
  })
  default = {}

  validation {
    condition     = contains(["filesystem", "gcs", "s3"], var.loki_storage.backend)
    error_message = "loki_storage.backend must be filesystem, gcs or s3."
  }
}

variable "loki_s3_credentials" {
  description = "Static S3 credentials for loki_storage.backend = s3 (null to rely on the platform identity)."
  type = object({
    access_key_id     = string
    secret_access_key = string
  })
  default   = null
  sensitive = true
}

variable "loki_retention_period" {
  description = "How long Loki keeps logs (compactor retention), e.g. 720h = 30 days."
  type        = string
  default     = "720h"
}

variable "loki_ingestion_rate_mb" {
  description = "Per-tenant ingestion rate limit in MB/s (burst is twice this)."
  type        = number
  default     = 8
}

variable "loki_storage_size" {
  description = "PVC size for the Loki single-binary pod (WAL, index cache; chunks too when backend = filesystem)."
  type        = string
  default     = "10Gi"
}

variable "loki_resources" {
  description = "Requests/limits for the Loki pod."
  type = object({
    requests = optional(map(string), { cpu = "200m", memory = "512Mi" })
    limits   = optional(map(string), { cpu = "1", memory = "1536Mi" })
  })
  default = {}
}

variable "loki_service_account_annotations" {
  description = "Annotations for the Loki ServiceAccount (e.g. iam.gke.io/gcp-service-account or eks.amazonaws.com/role-arn). Not needed with GKE Workload Identity principal:// bindings."
  type        = map(string)
  default     = {}
}

variable "loki_values" {
  description = "Extra values for the loki chart, deep-merged by Helm on top of the module defaults."
  type        = any
  default     = {}
}

# --- Tempo ---

variable "enable_tempo" {
  description = "Install Tempo (monolithic) in the monitoring namespace."
  type        = bool
  default     = false
}

variable "tempo_storage" {
  description = "Where Tempo keeps trace blocks: local (PVC only), gcs or s3 (bucket required). Same auth notes as loki_storage; the ServiceAccount is <namespace>/tempo."
  type = object({
    backend = optional(string, "local")
    bucket  = optional(string)
    s3 = optional(object({
      endpoint         = optional(string)
      region           = optional(string)
      force_path_style = optional(bool, false)
      insecure         = optional(bool, false)
    }))
  })
  default = {}

  validation {
    condition     = contains(["local", "gcs", "s3"], var.tempo_storage.backend)
    error_message = "tempo_storage.backend must be local, gcs or s3."
  }
}

variable "tempo_s3_credentials" {
  description = "Static S3 credentials for tempo_storage.backend = s3 (null to rely on the platform identity)."
  type = object({
    access_key_id     = string
    secret_access_key = string
  })
  default   = null
  sensitive = true
}

variable "tempo_retention" {
  description = "How long Tempo keeps trace blocks, e.g. 336h = 14 days."
  type        = string
  default     = "336h"
}

variable "tempo_storage_size" {
  description = "PVC size for the Tempo pod (WAL and local blocks before upload; everything when backend = local)."
  type        = string
  default     = "10Gi"
}

variable "tempo_metrics_generator_enabled" {
  description = "Derive RED metrics (span-metrics) and the service graph from traces and remote-write them to the in-cluster Prometheus."
  type        = bool
  default     = true
}

variable "tempo_resources" {
  description = "Requests/limits for the Tempo pod."
  type = object({
    requests = optional(map(string), { cpu = "200m", memory = "768Mi" })
    limits   = optional(map(string), { cpu = "1", memory = "1536Mi" })
  })
  default = {}
}

variable "tempo_service_account_annotations" {
  description = "Annotations for the Tempo ServiceAccount (see loki_service_account_annotations)."
  type        = map(string)
  default     = {}
}

variable "tempo_values" {
  description = "Extra values for the tempo chart, deep-merged by Helm on top of the module defaults."
  type        = any
  default     = {}
}

# --- Prometheus receivers / Grafana datasources for the OTel stack ---

variable "prometheus_otlp_receiver_enabled" {
  description = "Enable Prometheus' OTLP receiver (/api/v1/otlp). Defaults to enable_otel_collector."
  type        = bool
  default     = null
}

variable "prometheus_remote_write_receiver_enabled" {
  description = "Enable Prometheus' remote-write receiver (/api/v1/write). Defaults to enable_tempo && tempo_metrics_generator_enabled."
  type        = bool
  default     = null
}

variable "prometheus_otlp_promote_resource_attributes" {
  description = "OTLP resource attributes Prometheus promotes to metric labels."
  type        = list(string)
  default = [
    "service.name",
    "service.namespace",
    "service.instance.id",
    "deployment.environment",
    "k8s.cluster.name",
    "k8s.namespace.name",
    "k8s.pod.name",
    "k8s.container.name",
    "k8s.deployment.name",
  ]
}

variable "grafana_provision_otel_datasources" {
  description = "Provision Loki and Tempo datasources in Grafana (with trace/log/metric correlation) when those components are enabled. Set false to manage them elsewhere (e.g. the grafana Terraform provider)."
  type        = bool
  default     = true
}

variable "grafana_metrics_datasource_uid" {
  description = "UID of the Prometheus-compatible datasource Tempo uses for the service map and span metrics (kube-prometheus-stack provisions 'prometheus')."
  type        = string
  default     = "prometheus"
}

locals {
  otel_collector_enabled = var.enable_otel_operator && var.enable_otel_collector

  otel_agent_name   = "otel-agent"
  otel_gateway_name = "otel-gateway"
  # The operator names the Service <cr-name>-collector.
  otel_gateway_service   = "${local.otel_gateway_name}-collector.${var.namespace}.svc.cluster.local"
  otel_gateway_otlp_grpc = "${local.otel_gateway_service}:4317"
  otel_gateway_otlp_http = "http://${local.otel_gateway_service}:4318"

  loki_url        = var.enable_loki ? "http://loki.${var.namespace}.svc.cluster.local:3100" : null
  tempo_url       = var.enable_tempo ? "http://tempo.${var.namespace}.svc.cluster.local:3200" : null
  tempo_otlp_grpc = "tempo.${var.namespace}.svc.cluster.local:4317"
  prometheus_url  = "http://${local.release_name}-prometheus.${var.namespace}.svc.cluster.local:9090"

  metrics_to_prometheus = var.metrics_store == "prometheus" && var.prometheus_enabled
  metrics_to_mimir      = var.metrics_store == "mimir"

  prometheus_otlp_receiver_enabled         = var.prometheus_enabled && coalesce(var.prometheus_otlp_receiver_enabled, local.otel_collector_enabled && local.metrics_to_prometheus)
  prometheus_remote_write_receiver_enabled = var.prometheus_enabled && coalesce(var.prometheus_remote_write_receiver_enabled, var.enable_tempo && var.tempo_metrics_generator_enabled && local.metrics_to_prometheus)

  # Grafana datasources with correlation: Loki log lines carrying trace_id=<id>
  # link to Tempo; Tempo spans link back to Loki (by service name and trace id)
  # and to the metrics datasource for the service map / span metrics.
  grafana_otel_datasources = concat(
    var.grafana_provision_otel_datasources && var.enable_loki ? [
      {
        name   = "Loki"
        type   = "loki"
        uid    = "loki"
        access = "proxy"
        url    = local.loki_url
        jsonData = {
          derivedFields = [
            {
              name            = "TraceID"
              matcherType     = "regex"
              matcherRegex    = "(?:trace_id|traceID|traceId)[=:\\s\"]+([0-9a-fA-F]{16,32})"
              url             = "$${__value.raw}"
              urlDisplayLabel = "Trace"
              datasourceUid   = "tempo"
            },
          ]
        }
      },
    ] : [],
    var.grafana_provision_otel_datasources && var.enable_tempo ? [
      {
        name   = "Tempo"
        type   = "tempo"
        uid    = "tempo"
        access = "proxy"
        url    = local.tempo_url
        jsonData = {
          tracesToLogsV2 = {
            datasourceUid      = "loki"
            spanStartTimeShift = "-1h"
            spanEndTimeShift   = "1h"
            filterByTraceID    = true
            filterBySpanID     = false
            tags = [
              { key = "service.name", value = "service_name" },
            ]
          }
          tracesToMetrics = {
            datasourceUid      = var.grafana_metrics_datasource_uid
            spanStartTimeShift = "-1h"
            spanEndTimeShift   = "1h"
          }
          serviceMap = {
            datasourceUid = var.grafana_metrics_datasource_uid
          }
          nodeGraph = {
            enabled = true
          }
          lokiSearch = {
            datasourceUid = "loki"
          }
        }
      },
    ] : [],
  )
}
