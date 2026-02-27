output "folder_url" {
  description = "Direct link to the TechMart SLOs folder in Grafana."
  value       = "${trimsuffix(var.grafana_url, "/")}//dashboards/f/${grafana_folder.techmart.uid}"
}

output "dashboard_urls" {
  description = "Direct links to each deployed dashboard."
  value = {
    slo_overview       = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/slo-overview.json")).uid}"
    checkout_slo       = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/checkout-slo.json")).uid}"
    checkout_breakdown = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/checkout-breakdown.json")).uid}"
    cuj_slo            = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/cuj-slo.json")).uid}"
    job_lifecycle      = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/job-lifecycle.json")).uid}"
  }
}
