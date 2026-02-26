variable "grafana_url" {
  description = "Grafana Cloud instance URL, e.g. https://your-org.grafana.net"
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana API key with Editor or Admin role. Set in terraform.tfvars (gitignored) or TF_VAR_grafana_api_key env var."
  type        = string
  sensitive   = true
}

variable "folder_title" {
  description = "Name of the Grafana folder that will contain all TechMart dashboards."
  type        = string
  default     = "TechMart SLOs"
}
