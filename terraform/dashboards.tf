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
