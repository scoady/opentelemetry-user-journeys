# ─────────────────────────────────────────────────────────────────────────────
# TechMart Grafana SLOs
#
# 16 SLOs — availability + latency for each Critical User Journey:
#
#   CUJ                  Availability SLO   Latency SLO
#   ─────────────────    ────────────────   ──────────────────
#   checkout             99.9 % success     p99 < 2 s    (le="2000" bucket)
#   product-discovery    99.9 % success     p99 < 1 s    (le="1000" bucket)
#   order-lookup         99.9 % success     p99 < 1 s    (le="1000" bucket)
#   product-search       99.9 % success     p99 < 500ms  (le="500" bucket)
#   product-review       99.9 % success     p99 < 1 s    (le="1000" bucket)
#   order-history        99.9 % success     p99 < 1 s    (le="1000" bucket)
#   product-upload       99.9 % success     p99 < 2 s    (le="2000" bucket)
#   product-upload-job   99.9 % success     p99 < 10 s   (le="10000" bucket)
#
# Availability uses the native "ratio" query type (good/total counters).
# Latency uses "freeform" with a histogram bucket fraction — the spanmetrics
# connector emits explicit buckets 10ms…10s, so le="2000", le="1000", le="500"
# exist as exact boundaries in techmart_duration_milliseconds_bucket.
#
# Both fast-burn (14.4×) and slow-burn (6×) alert rules are generated
# automatically by Grafana when the `alerting {}` block is present.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Prometheus datasource UID on the Grafana Cloud stack
  prom_uid = "grafanacloud-prom"
}

# ── Checkout ──────────────────────────────────────────────────────────────────

resource "grafana_slo" "checkout_availability" {
  name        = "Checkout — Availability"
  description = "99.9 % of cuj.checkout spans must succeed (not STATUS_CODE_ERROR). Error budget: ~43 minutes of downtime per 30 days."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.checkout\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.checkout\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "checkout"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Checkout Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Checkout error budget burning >14.4× rate. At this rate the full 30-day budget is consumed in ~2 days. Investigate immediately."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Checkout Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Checkout error budget burning >6× rate. Budget will exhaust in ~5 days if sustained. Check recent deploys and DB health."
      }
    }
  }
}

resource "grafana_slo" "checkout_latency" {
  name        = "Checkout — Latency p99 < 2 s"
  description = "99.9 % of cuj.checkout requests must complete within 2000 ms. Measured via the le=2000 histogram bucket (exact boundary in the spanmetrics collector config)."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      # Fraction of requests completing within 2000 ms.
      # le="+Inf" == total request count.
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.checkout\", le=\"2000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.checkout\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "checkout"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Checkout Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Checkout p99 latency SLO burning >14.4× rate. More than 0.1 % of requests are exceeding 2 s. Check inventory-svc delay (helm upgrade --set inventorySvc.artificialDelayMs=0) and DB query times."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Checkout Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Checkout p99 latency SLO burning >6× rate. Review inventory-svc latency on the Checkout CUJ Breakdown dashboard."
      }
    }
  }
}

# ── Product Discovery ─────────────────────────────────────────────────────────

resource "grafana_slo" "product_discovery_availability" {
  name        = "Product Discovery — Availability"
  description = "99.9 % of cuj.product-discovery spans must succeed. Covers GET /api/products and GET /api/products/:id."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.product-discovery\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.product-discovery\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-discovery"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Discovery Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product discovery error budget burning >14.4× rate. Customers cannot browse or search products."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Discovery Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product discovery error budget burning >6× rate. Investigate API and DB errors."
      }
    }
  }
}

resource "grafana_slo" "product_discovery_latency" {
  name        = "Product Discovery — Latency p99 < 1 s"
  description = "99.9 % of cuj.product-discovery requests must complete within 1000 ms. Measured via the le=1000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-discovery\", le=\"1000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-discovery\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-discovery"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Discovery Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product discovery p99 latency SLO burning >14.4× rate. More than 0.1 % of product page loads exceeding 1 s."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Discovery Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product discovery p99 latency SLO burning >6× rate. Check DB query performance on the products table."
      }
    }
  }
}

# ── Order Lookup ──────────────────────────────────────────────────────────────

resource "grafana_slo" "order_lookup_availability" {
  name        = "Order Lookup — Availability"
  description = "99.9 % of cuj.order-lookup spans must succeed. Covers GET /api/orders."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.order-lookup\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.order-lookup\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "order-lookup"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Order Lookup Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Order lookup error budget burning >14.4× rate. Customers cannot view their order history."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Order Lookup Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Order lookup error budget burning >6× rate. Investigate orders table query errors."
      }
    }
  }
}

resource "grafana_slo" "order_lookup_latency" {
  name        = "Order Lookup — Latency p99 < 1 s"
  description = "99.9 % of cuj.order-lookup requests must complete within 1000 ms. Measured via the le=1000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.order-lookup\", le=\"1000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.order-lookup\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "order-lookup"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Order Lookup Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Order lookup p99 latency SLO burning >14.4× rate. More than 0.1 % of order history requests exceeding 1 s."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Order Lookup Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Order lookup p99 latency SLO burning >6× rate. Check orders JOIN query performance."
      }
    }
  }
}

# ── Product Search ────────────────────────────────────────────────────────────

resource "grafana_slo" "product_search_availability" {
  name        = "Product Search — Availability"
  description = "99.9 % of cuj.product-search spans must succeed. Covers GET /api/products/search."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.product-search\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.product-search\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-search"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Search Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product search error budget burning >14.4× rate. Customers cannot search or filter products."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Search Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product search error budget burning >6× rate. Investigate search query errors and DB index health."
      }
    }
  }
}

resource "grafana_slo" "product_search_latency" {
  name        = "Product Search — Latency p99 < 500 ms"
  description = "99.9 % of cuj.product-search requests must complete within 500 ms. Measured via the le=500 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-search\", le=\"500\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-search\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-search"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Search Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product search p99 latency SLO burning >14.4× rate. More than 0.1 % of search requests exceeding 500 ms. Check ILIKE query performance and DB indexes."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Search Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product search p99 latency SLO burning >6× rate. Review search query performance and products table indexes."
      }
    }
  }
}

# ── Product Review ────────────────────────────────────────────────────────────

resource "grafana_slo" "product_review_availability" {
  name        = "Product Review — Availability"
  description = "99.9 % of cuj.product-review spans must succeed. Covers GET and POST /api/products/:id/reviews."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.product-review\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.product-review\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-review"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Review Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product review error budget burning >14.4× rate. Customers cannot read or write reviews."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Review Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product review error budget burning >6× rate. Investigate reviews table query errors."
      }
    }
  }
}

resource "grafana_slo" "product_review_latency" {
  name        = "Product Review — Latency p99 < 1 s"
  description = "99.9 % of cuj.product-review requests must complete within 1000 ms. Measured via the le=1000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-review\", le=\"1000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-review\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-review"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Review Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product review p99 latency SLO burning >14.4× rate. More than 0.1 % of review requests exceeding 1 s."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Review Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product review p99 latency SLO burning >6× rate. Check reviews table index and JOIN performance."
      }
    }
  }
}

# ── Order History ─────────────────────────────────────────────────────────────

resource "grafana_slo" "order_history_availability" {
  name        = "Order History — Availability"
  description = "99.9 % of cuj.order-history spans must succeed. Covers GET /api/orders?email=."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.order-history\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.order-history\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "order-history"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Order History Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Order history error budget burning >14.4× rate. Customers cannot look up past orders by email."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Order History Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Order history error budget burning >6× rate. Investigate orders table query errors."
      }
    }
  }
}

resource "grafana_slo" "order_history_latency" {
  name        = "Order History — Latency p99 < 1 s"
  description = "99.9 % of cuj.order-history requests must complete within 1000 ms. Measured via the le=1000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.order-history\", le=\"1000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.order-history\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "order-history"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Order History Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Order history p99 latency SLO burning >14.4× rate. More than 0.1 % of order history requests exceeding 1 s."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Order History Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Order history p99 latency SLO burning >6× rate. Check customer_email index and JOIN performance."
      }
    }
  }
}

# ── Product Upload (async via Kafka) ──────────────────────────────────────────

resource "grafana_slo" "product_upload_availability" {
  name        = "Product Upload — Availability"
  description = "99.9 % of cuj.product-upload spans must succeed. Covers POST /api/admin/upload-products (API-side: job creation + Kafka produce)."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.product-upload\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.product-upload\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-upload"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Upload Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload error budget burning >14.4× rate. Admin bulk uploads are failing at the API/Kafka produce stage."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Upload Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload error budget burning >6× rate. Check Kafka broker connectivity and upload_jobs table."
      }
    }
  }
}

resource "grafana_slo" "product_upload_latency" {
  name        = "Product Upload — Latency p99 < 2 s"
  description = "99.9 % of cuj.product-upload requests must complete within 2000 ms. Covers job creation + Kafka produce. Measured via the le=2000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-upload\", le=\"2000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-upload\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-upload"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Upload Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload p99 latency SLO burning >14.4× rate. More than 0.1 % of uploads exceeding 2 s. Check Kafka broker health and DB write performance."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Upload Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload p99 latency SLO burning >6× rate. Review Kafka produce latency and upload_jobs INSERT times."
      }
    }
  }
}

# ── Product Upload Job (Kafka consumer processing) ───────────────────────────

resource "grafana_slo" "product_upload_job_availability" {
  name        = "Product Upload Job — Availability"
  description = "99.9 % of cuj.product-upload-job spans must succeed. Covers Kafka consume → batch INSERT → job status update in the product-worker service."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "ratio"
    ratio {
      success_metric = "techmart_calls_total{span_name=\"cuj.product-upload-job\", status_code!=\"STATUS_CODE_ERROR\"}"
      total_metric   = "techmart_calls_total{span_name=\"cuj.product-upload-job\"}"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-upload-job"
  }
  label {
    key   = "slo_type"
    value = "availability"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Upload Job Availability — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload job error budget burning >14.4× rate. Kafka consumer is failing to process batch inserts."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Upload Job Availability — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload job error budget burning >6× rate. Check product-worker logs and DB connectivity."
      }
    }
  }
}

resource "grafana_slo" "product_upload_job_latency" {
  name        = "Product Upload Job — Latency p99 < 10 s"
  description = "99.9 % of cuj.product-upload-job requests must complete within 10000 ms. Covers Kafka consume through batch INSERT of products. Measured via the le=10000 histogram bucket."
  folder_uid  = grafana_folder.techmart.uid

  destination_datasource {
    uid = local.prom_uid
  }

  query {
    type = "freeform"
    freeform {
      query = "sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-upload-job\", le=\"10000\"}[$__rate_interval])) / sum(rate(techmart_duration_milliseconds_bucket{span_name=\"cuj.product-upload-job\", le=\"+Inf\"}[$__rate_interval]))"
    }
  }

  objectives {
    value  = 0.999
    window = "30d"
  }

  label {
    key   = "cuj"
    value = "product-upload-job"
  }
  label {
    key   = "slo_type"
    value = "latency"
  }

  alerting {
    fastburn {
      label {
        key   = "severity"
        value = "critical"
      }
      annotation {
        key   = "name"
        value = "Product Upload Job Latency — Fast Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload job p99 latency SLO burning >14.4× rate. More than 0.1 % of batch inserts exceeding 10 s. Check product-worker throughput and DB write performance."
      }
    }
    slowburn {
      label {
        key   = "severity"
        value = "warning"
      }
      annotation {
        key   = "name"
        value = "Product Upload Job Latency — Slow Burn"
      }
      annotation {
        key   = "description"
        value = "Product upload job p99 latency SLO burning >6× rate. Review batch INSERT sizes and DB connection pool health."
      }
    }
  }
}
