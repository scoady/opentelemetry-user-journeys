# ── Folder ────────────────────────────────────────────────────────────────────
resource "grafana_folder" "techmart" {
  title = var.folder_title
  uid   = "techmart-slos"
}

# ── Dashboards ────────────────────────────────────────────────────────────────
# Each dashboard is stored as a self-contained JSON file in ./grafana/dashboards/.
# The JSON uses a $datasource template variable so users can bind any Prometheus
# source at view time — no hardcoded datasource UIDs needed here.
#
# overwrite = true means `terraform apply` will update an existing dashboard
# in-place rather than error if the UID already exists in Grafana.

resource "grafana_dashboard" "slo_overview" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/slo-overview.json")
  overwrite   = true
}

resource "grafana_dashboard" "checkout_slo" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/checkout-slo.json")
  overwrite   = true
}

resource "grafana_dashboard" "checkout_breakdown" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/checkout-breakdown.json")
  overwrite   = true
}

resource "grafana_dashboard" "cuj_slo" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/cuj-slo.json")
  overwrite   = true
}

resource "grafana_dashboard" "job_lifecycle" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/job-lifecycle.json")
  overwrite   = true
}

resource "grafana_dashboard" "observability_guide" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/observability-guide.json")
  overwrite   = true
}

resource "grafana_dashboard" "executive_summary" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/executive-summary.json")
  overwrite   = true
}

resource "grafana_dashboard" "cuj_deep_dive" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/cuj-deep-dive.json")
  overwrite   = true
}

resource "grafana_dashboard" "latency_analysis" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/latency-analysis.json")
  overwrite   = true
}

resource "grafana_dashboard" "traffic_errors" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/traffic-errors.json")
  overwrite   = true
}

resource "grafana_dashboard" "admin_embed" {
  folder      = grafana_folder.techmart.uid
  config_json = file("${path.module}/grafana/dashboards/admin-embed.json")
  overwrite   = true
}

# Public (no-auth) version of the admin embed dashboard for iframe embedding.
resource "grafana_dashboard_public" "admin_embed" {
  dashboard_uid          = jsondecode(file("${path.module}/grafana/dashboards/admin-embed.json")).uid
  is_enabled             = true
  time_selection_enabled = false
  annotations_enabled    = false

  depends_on = [grafana_dashboard.admin_embed]
}
