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
    job_lifecycle       = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/job-lifecycle.json")).uid}"
    observability_guide  = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/observability-guide.json")).uid}"
    executive_summary   = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/executive-summary.json")).uid}"
    cuj_deep_dive       = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/cuj-deep-dive.json")).uid}"
    latency_analysis    = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/latency-analysis.json")).uid}"
    traffic_errors      = "${trimsuffix(var.grafana_url, "/")}/d/${jsondecode(file("${path.module}/grafana/dashboards/traffic-errors.json")).uid}"
  }
}
