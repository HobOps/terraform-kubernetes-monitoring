# Example: complete cluster monitoring

Thin wrapper around the root module. Cluster-specific values live in
`locals.tf`.

## Prerequisites

- `kubectl` context matching `local.kube_context`
- Shared Gateway (for example from `terraform-kubernetes-bootstrap`) if using `grafana_hostname`
- `terraform`

## Setup

1. Edit `locals.tf` and `backend.tf` for your environment.
2. Apply:

```bash
cd examples/complete
make init
terraform apply
```

## Grafana admin password

```bash
terraform output -raw grafana_admin_password
```

When `grafana_hostname` is set, open `https://<grafana_hostname>/` and log in as `admin`.
