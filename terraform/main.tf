terraform {
  required_version = ">= 1.5"

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
