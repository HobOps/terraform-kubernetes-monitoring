# OTel Collector in two pieces, both reconciled by the operator:
#   - agent (DaemonSet): tails every container log under /var/log/pods, tags it
#     with Kubernetes metadata and forwards it to the gateway over OTLP.
#   - gateway (Deployment): receives OTLP from the apps (and the agents), batches
#     and fans out traces -> Tempo, logs -> Loki, metrics -> Prometheus (OTLP
#     receiver) or Mimir (metrics_store = "mimir"). Apps only ever talk to the
#     gateway.
# Nothing is exposed outside the cluster (ClusterIP services only).

resource "kubernetes_service_account" "otel_agent" {
  count = local.otel_collector_enabled ? 1 : 0

  metadata {
    name      = local.otel_agent_name
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace.monitoring]
}

resource "kubernetes_service_account" "otel_gateway" {
  count = local.otel_collector_enabled ? 1 : 0

  metadata {
    name      = local.otel_gateway_name
    namespace = var.namespace
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# Read-only access for the k8sattributes processor (pod -> workload metadata)
# and the kubeletstats receiver (node stats through the kubelet API).
resource "kubernetes_cluster_role" "otel_collector" {
  count = local.otel_collector_enabled ? 1 : 0

  metadata {
    name = "${var.namespace}-otel-collector"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "deployments", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes/stats", "nodes/proxy"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "otel_collector" {
  count = local.otel_collector_enabled ? 1 : 0

  metadata {
    name = "${var.namespace}-otel-collector"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_collector[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_agent[0].metadata[0].name
    namespace = var.namespace
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_gateway[0].metadata[0].name
    namespace = var.namespace
  }
}

locals {
  # Shared processors: cap memory, enrich with Kubernetes metadata, stamp the
  # cluster name, then batch.
  otel_k8sattributes = {
    auth_type   = "serviceAccount"
    passthrough = false
    extract = {
      metadata = [
        "k8s.namespace.name",
        "k8s.pod.name",
        "k8s.pod.uid",
        "k8s.pod.start_time",
        "k8s.deployment.name",
        "k8s.statefulset.name",
        "k8s.daemonset.name",
        "k8s.cronjob.name",
        "k8s.job.name",
        "k8s.node.name",
        "k8s.container.name",
      ]
      labels = [
        { tag_name = "app", key = "app.kubernetes.io/name", from = "pod" },
        { tag_name = "app.instance", key = "app.kubernetes.io/instance", from = "pod" },
      ]
    }
    # Attribute-based association first (data forwarded by the agent already
    # carries pod uid/name); the connection IP is the fallback for apps that
    # send OTLP straight to the gateway.
    pod_association = [
      { sources = [{ from = "resource_attribute", name = "k8s.pod.uid" }] },
      { sources = [{ from = "resource_attribute", name = "k8s.pod.name" }, { from = "resource_attribute", name = "k8s.namespace.name" }] },
      { sources = [{ from = "connection" }] },
    ]
  }

  otel_common_processors = {
    memory_limiter = {
      check_interval         = "5s"
      limit_percentage       = 80
      spike_limit_percentage = 25
    }
    resource = {
      attributes = [
        { key = "k8s.cluster.name", value = var.cluster_name, action = "upsert" },
      ]
    }
    batch = {
      timeout         = "5s"
      send_batch_size = 1024
    }
  }

  otel_agent_config = {
    receivers = merge(
      {
        filelog = {
          include = ["/var/log/pods/*/*/*.log"]
          exclude = concat(
            [
              "/var/log/pods/${var.namespace}_${local.otel_agent_name}-collector-*/*/*.log",
              "/var/log/pods/${var.namespace}_${local.otel_gateway_name}-collector-*/*/*.log",
            ],
            var.otel_agent_log_exclude,
          )
          start_at          = "end"
          include_file_path = true
          include_file_name = false
          operators = [
            {
              id                         = "container-parser"
              type                       = "container"
              add_metadata_from_filepath = true
            },
          ]
        }
      },
      var.otel_agent_kubeletstats_enabled ? {
        kubeletstats = {
          collection_interval  = "30s"
          auth_type            = "serviceAccount"
          endpoint             = "https://$${env:K8S_NODE_NAME}:10250"
          insecure_skip_verify = true
        }
      } : {},
    )
    processors = merge(local.otel_common_processors, {
      k8sattributes = merge(local.otel_k8sattributes, {
        filter = { node_from_env_var = "K8S_NODE_NAME" }
      })
    })
    exporters = {
      otlp = {
        endpoint = local.otel_gateway_otlp_grpc
        tls      = { insecure = true }
      }
    }
    extensions = {
      health_check = { endpoint = "0.0.0.0:13133" }
    }
    service = {
      extensions = ["health_check"]
      pipelines = merge(
        {
          logs = {
            receivers  = ["filelog"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["otlp"]
          }
        },
        var.otel_agent_kubeletstats_enabled ? {
          metrics = {
            receivers  = ["kubeletstats"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["otlp"]
          }
        } : {},
      )
    }
  }

  otel_gateway_exporters = merge(
    var.enable_tempo ? {
      "otlp/tempo" = {
        endpoint = local.tempo_otlp_grpc
        tls      = { insecure = true }
      }
    } : {},
    var.enable_loki ? {
      "otlphttp/loki" = {
        endpoint = "${local.loki_url}/otlp"
        tls      = { insecure = true }
      }
    } : {},
    local.prometheus_otlp_receiver_enabled ? {
      "otlphttp/prometheus" = {
        endpoint = "${local.prometheus_url}/api/v1/otlp"
        tls      = { insecure = true }
      }
    } : {},
    local.metrics_to_mimir && local.mimir_otlp_url != null ? {
      "otlphttp/mimir" = merge(
        {
          endpoint = local.mimir_otlp_url
          tls      = { insecure = true }
        },
        length(local.mimir_tenant_headers) > 0 ? { headers = local.mimir_tenant_headers } : {},
      )
    } : {},
  )

  otel_gateway_metrics_exporters = concat(
    local.prometheus_otlp_receiver_enabled ? ["otlphttp/prometheus"] : [],
    local.metrics_to_mimir && local.mimir_otlp_url != null ? ["otlphttp/mimir"] : [],
  )

  otel_gateway_config = {
    receivers = {
      otlp = {
        protocols = {
          grpc = { endpoint = "0.0.0.0:4317" }
          http = { endpoint = "0.0.0.0:4318" }
        }
      }
    }
    processors = merge(local.otel_common_processors, {
      k8sattributes = local.otel_k8sattributes
    })
    exporters = local.otel_gateway_exporters
    extensions = {
      health_check = { endpoint = "0.0.0.0:13133" }
    }
    service = {
      extensions = ["health_check"]
      pipelines = merge(
        var.enable_tempo ? {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["otlp/tempo"]
          }
        } : {},
        var.enable_loki ? {
          logs = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = ["otlphttp/loki"]
          }
        } : {},
        length(local.otel_gateway_metrics_exporters) > 0 ? {
          metrics = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "k8sattributes", "resource", "batch"]
            exporters  = local.otel_gateway_metrics_exporters
          }
        } : {},
      )
    }
  }
}

resource "kubectl_manifest" "otel_agent" {
  count = local.otel_collector_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "opentelemetry.io/v1beta1"
    kind       = "OpenTelemetryCollector"
    metadata = {
      name      = local.otel_agent_name
      namespace = var.namespace
    }
    spec = {
      mode            = "daemonset"
      upgradeStrategy = "automatic"
      serviceAccount  = kubernetes_service_account.otel_agent[0].metadata[0].name
      resources       = var.otel_agent_resources
      # Container log files are root-owned (0640) on most CRI setups; the
      # agent runs as root to read them, like the upstream chart's logs preset.
      securityContext = {
        runAsUser  = 0
        runAsGroup = 0
      }
      tolerations = [{ operator = "Exists" }]
      env = [
        {
          name      = "K8S_NODE_NAME"
          valueFrom = { fieldRef = { fieldPath = "spec.nodeName" } }
        },
      ]
      volumes = [
        { name = "varlogpods", hostPath = { path = "/var/log/pods" } },
      ]
      volumeMounts = [
        { name = "varlogpods", mountPath = "/var/log/pods", readOnly = true },
      ]
      observability = {
        metrics = { enableMetrics = true }
      }
      config = local.otel_agent_config
    }
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.otel_operator,
    kubernetes_cluster_role_binding.otel_collector,
    kubectl_manifest.otel_gateway,
  ]
}

resource "kubectl_manifest" "otel_gateway" {
  count = local.otel_collector_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "opentelemetry.io/v1beta1"
    kind       = "OpenTelemetryCollector"
    metadata = {
      name      = local.otel_gateway_name
      namespace = var.namespace
    }
    spec = {
      mode            = "deployment"
      upgradeStrategy = "automatic"
      replicas        = var.otel_gateway_replicas
      serviceAccount  = kubernetes_service_account.otel_gateway[0].metadata[0].name
      resources       = var.otel_gateway_resources
      observability = {
        metrics = { enableMetrics = true }
      }
      config = local.otel_gateway_config
    }
  })

  wait_for_rollout = false

  depends_on = [
    helm_release.otel_operator,
    kubernetes_cluster_role_binding.otel_collector,
    helm_release.loki,
    helm_release.tempo,
  ]

  lifecycle {
    precondition {
      condition     = length(local.otel_gateway_exporters) > 0
      error_message = "enable_otel_collector needs at least one backend: enable_loki, enable_tempo, the Prometheus OTLP receiver or Mimir."
    }
    precondition {
      condition     = !local.metrics_to_mimir || var.enable_mimir
      error_message = "metrics_store=mimir needs enable_mimir=true (the gateway sends OTLP to the in-cluster Mimir)."
    }
  }
}
