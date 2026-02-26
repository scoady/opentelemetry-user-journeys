# ─────────────────────────────────────────────────────────────────────────────
# TechMart Grafana SLOs
#
# 6 SLOs — availability + latency for each Critical User Journey:
#
#   CUJ                  Availability SLO   Latency SLO
#   ─────────────────    ────────────────   ──────────────────
#   checkout             99.9 % success     p99 < 2 s  (le="2000" bucket)
#   product-discovery    99.9 % success     p99 < 1 s  (le="1000" bucket)
#   order-lookup         99.9 % success     p99 < 1 s  (le="1000" bucket)
#
# Availability uses the native "ratio" query type (good/total counters).
# Latency uses "freeform" with a histogram bucket fraction — the spanmetrics
# connector emits explicit buckets 10ms…10s, so le="2000" and le="1000"
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
