provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = local.kube_context
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = local.kube_context
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = local.kube_context
}
