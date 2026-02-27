terraform {
  required_version = ">= 1.5"

  # State stored as Kubernetes Secret: tfstate-default-techmart in cicd namespace.
  # Auth is environment-specific — pass at init time:
  #   Local:   terraform init -backend-config="config_path=$HOME/.kube/config"
  #   Jenkins: terraform init -backend-config="in_cluster_config=true"
  backend "kubernetes" {
    secret_suffix = "techmart"
    namespace     = "cicd"
  }

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.7"
    }
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_api_key
}
