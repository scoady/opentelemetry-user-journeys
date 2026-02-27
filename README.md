# TechMart — Observability Demo with OpenTelemetry, SLOs, and Grafana Cloud

A fully instrumented 3-tier web store running on a local Kubernetes cluster (kind), demonstrating end-to-end observability across synchronous HTTP services and asynchronous Kafka-based job processing.

## What This Demonstrates

| Observability Pattern | Implementation | Signal Type |
|-----------------------|---------------|-------------|
| **Distributed Tracing** | OTel auto-instrumentation across 4 services | Traces |
| **Trace Context Propagation** | W3C TraceContext + Baggage across HTTP and Kafka | Traces |
| **RED Metrics from Traces** | Spanmetrics connector derives rate/error/duration | Metrics (from traces) |
| **Service Level Objectives** | Terraform-managed Grafana SLOs with burn-rate alerting | Metrics |
| **Async Job Observability** | Parent-child traces through Kafka message headers | Traces |
| **Critical User Journeys** | Custom `cuj.name` span attributes + baggage propagation | Traces + Metrics |
| **CI/CD Pipeline** | Jenkins in-cluster with Kaniko builds + Helm deploys | - |

## Architecture

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                  webstore namespace                      │
                              │                                                         │
  Browser ──▶ Ingress ──▶ Frontend (nginx)                                              │
                              │                                                         │
                    /api/ ──▶ API (:3001) ──▶ PostgreSQL (:5432)                         │
                              │     │                                                   │
                              │     ├──▶ inventory-svc (:3002)                          │
                              │     │                                                   │
                              │     └──▶ Kafka (:9092) ──▶ product-worker               │
                              │                                                         │
                              │         k6 (traffic generator)                          │
                              └─────────────────────────────────────────────────────────┘

                              ┌─────────────────────────────────────────────────────────┐
                              │              observability namespace                     │
                              │                                                         │
                              │  OTel Collector ──▶ Grafana Cloud (Mimir + Tempo)        │
                              │      ▲                                                  │
                              │      │ OTLP (traces, metrics, logs)                     │
                              │      │                                                  │
                              └──────┼──────────────────────────────────────────────────┘
                                     │
                              All instrumented services
```

## Telemetry Signals

### Traces — The Foundation

Every service is auto-instrumented by the [OTel Operator](https://opentelemetry.io/docs/kubernetes/operator/). An `Instrumentation` CR triggers an init-container injection that loads the Node.js SDK at startup — no SDK code in application dependencies (only `@opentelemetry/api` for manual span attributes).

Auto-instrumented libraries:
- **HTTP** (`@opentelemetry/instrumentation-http`) — creates spans for every inbound/outbound HTTP request
- **Express** (`@opentelemetry/instrumentation-express`) — adds `http.route` attribute
- **pg** (`@opentelemetry/instrumentation-pg`) — creates spans for every SQL query
- **kafkajs** (`@opentelemetry/instrumentation-kafkajs`) — creates producer/consumer spans with trace context in message headers

All traces flow: **Services → OTLP → OTel Collector → Grafana Cloud Tempo**

### Metrics — Derived from Traces

TechMart uses **zero manual metrics instrumentation**. All metrics are derived from traces via the OTel collector's [spanmetrics connector](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/connector/spanmetrics):

```yaml
connectors:
  spanmetrics:
    namespace: techmart
    histogram:
      explicit:
        buckets: [10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2s, 5s, 10s]
    dimensions:
      - name: cuj.name           # Critical User Journey label
      - name: http.route
      - name: http.request.method
      - name: http.response.status_code
```

This generates:

| Metric | Type | Purpose |
|--------|------|---------|
| `techmart_calls_total` | Counter | Request count by span name, status code, CUJ |
| `techmart_duration_milliseconds_bucket` | Histogram | Latency distribution with explicit bucket boundaries |
| `techmart_duration_milliseconds_count` | Counter | Total request count (histogram companion) |
| `techmart_duration_milliseconds_sum` | Counter | Total duration (histogram companion) |

The `cuj.name` dimension is the key insight — it lets dashboards and SLOs filter metrics by **business-level user journey**, not just by endpoint or service.

All metrics flow: **Collector spanmetrics → OTLP → Grafana Cloud Mimir**

### How Traces Become SLOs

The interconnection between signals creates a powerful observability loop:

```
1. Application code calls withJourney('checkout', fn)
         │
         ▼
2. OTel SDK creates spans with cuj.name="checkout" attribute
         │
         ▼
3. Spans exported via OTLP to collector
         │
         ├──▶ Tempo (searchable traces)
         │
         └──▶ Spanmetrics connector
                  │
                  ▼
4. RED metrics: techmart_calls_total{span_name="cuj.checkout", status_code="..."}
                techmart_duration_milliseconds_bucket{span_name="cuj.checkout", le="..."}
                  │
                  ▼
5. Grafana SLO evaluates:
     Availability = success_calls / total_calls  (target: 99.9%)
     Latency      = calls_within_bucket / total  (target: 99.9% under threshold)
                  │
                  ▼
6. Burn-rate alerts fire if error budget consumption exceeds 14.4x (fast) or 6x (slow)
                  │
                  ▼
7. Engineer clicks through: Alert → SLO dashboard → Tempo trace → root cause
```

This means adding a new CUJ requires **zero metrics code** — just `withJourney('name', fn)` in the route handler, and the entire pipeline (traces → metrics → SLOs → alerts → dashboards) lights up automatically.

## Critical User Journeys

| CUJ | Type | Route / Trigger | SLO | Latency Target |
|-----|------|-----------------|-----|----------------|
| `product-discovery` | Sync | `GET /api/products` | 99.9% | p99 < 1s |
| `checkout` | Sync | `POST /api/orders` | 99.9% | p99 < 2s |
| `order-lookup` | Sync | `GET /api/orders/:id` | 99.9% | p99 < 1s |
| `product-search` | Sync | `GET /api/products/search` | 99.9% | p99 < 500ms |
| `product-review` | Sync | `GET/POST /api/products/:id/reviews` | 99.9% | p99 < 1s |
| `order-history` | Sync | `GET /api/orders?email=` | 99.9% | p99 < 1s |
| `product-upload` | Async | `POST /api/admin/upload-products` | 99.9% | p99 < 2s |
| `product-upload-job` | Async | Kafka consumer → batch INSERT | 99.9% | p99 < 10s |

Each CUJ gets exactly 2 Terraform-managed `grafana_slo` resources: one for availability (ratio query), one for latency (freeform histogram bucket query). Both include fastburn (14.4x, critical) and slowburn (6x, warning) alert rules.

## Trace Context Propagation

### Synchronous (HTTP)

```
API (withJourney) ──HTTP──▶ inventory-svc (cujBaggageMiddleware)
      │                              │
      │ W3C headers:                 │ Reads baggage, stamps cuj.name
      │   traceparent: 00-...        │ on its HTTP span. Child spans
      │   baggage: cuj.name=checkout │ inherit the context.
      ▼                              ▼
```

The originating service calls `withJourney('checkout', fn)` which:
1. Stamps `cuj.name` + `cuj.critical` on the parent HTTP span
2. Creates a child span `cuj.checkout`
3. Injects `cuj.name` into W3C Baggage context
4. Auto-instrumentation propagates `traceparent` + `baggage` headers on outbound HTTP

Downstream services use `cujBaggageMiddleware` to extract baggage and stamp CUJ attributes.

### Asynchronous (Kafka)

```
API (withJourney) ──produce──▶ Kafka ──consume──▶ product-worker (withJourney)
      │                                                  │
      │ kafkajs auto-instrumentation                     │ kafkajs auto-instrumentation
      │ injects traceparent + baggage                    │ extracts trace context from
      │ into Kafka message headers                       │ message headers, sets as
      │                                                  │ active context
      ▼                                                  ▼

Single trace spans both services:
  HTTP POST → cuj.product-upload → kafka.produce → kafka.receive → cuj.product-upload-job → DB
```

The `@opentelemetry/instrumentation-kafkajs` (injected by the OTel operator) handles context propagation through Kafka automatically:
- **Producer**: Creates `kafka.produce` span, injects `traceparent` + `baggage` into message headers
- **Consumer**: Extracts context from message headers, creates `kafka.receive` span as child of producer

The worker's `withJourney('product-upload-job', fn)` creates its CUJ span as a child of the `kafka.receive` span, giving a complete end-to-end trace.

## OTel Pipeline

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           OTel Operator                                  │
│                                                                          │
│  Instrumentation CR "techmart" (pre-install Helm hook)                   │
│    → Admission webhook injects init-container into annotated pods         │
│    → Init-container loads Node.js SDK + all auto-instrumentations        │
│    → SDK exports OTLP to collector at otel-collector.observability:4318   │
│    → Propagators: W3C tracecontext + baggage                             │
│    → Sampler: parentbased_traceidratio @ 100%                            │
└──────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        OTel Collector (Deployment)                        │
│                                                                          │
│  Receivers:   otlp (gRPC :4317, HTTP :4318)                              │
│  Connectors:  spanmetrics (techmart namespace, cuj.name dimension)        │
│  Processors:  batch (1s timeout, 1024 batch size)                        │
│  Exporters:   otlp_http/grafana (Grafana Cloud OTLP gateway)             │
│               debug (console output)                                     │
│                                                                          │
│  Pipelines:                                                              │
│    traces:   otlp → batch → [grafana, debug, spanmetrics]                │
│    metrics:  [otlp, spanmetrics] → batch → [grafana, debug]              │
│    logs:     otlp → batch → [grafana, debug]                             │
└──────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         Grafana Cloud                                     │
│                                                                          │
│  Tempo      — Distributed traces (search by trace ID, CUJ, service)     │
│  Mimir      — Prometheus-compatible metrics (spanmetrics + SLO queries)  │
│  SLOs       — 16 grafana_slo resources with burn-rate alerting           │
│  Dashboards — SLO overview (per-CUJ stats) + CUJ comparison (burn rates)│
└──────────────────────────────────────────────────────────────────────────┘
```

## Grafana Dashboards

### SLO Overview Dashboard
Per-CUJ rows showing:
- **Success Rate** (1h) — stat panel, instant query
- **p99 Latency** — stat panel, `histogram_quantile(0.99, ...)`
- **Request Rate** — stat panel, `sum(rate(...))`
- **Error Rate** — timeseries, errors over time

### CUJ Comparison Dashboard
Cross-CUJ comparison with:
- **Burn Rate (1h / 6h)** — stat panels per CUJ, color-coded thresholds
- **Success Rate** — stat + timeseries overlay of all CUJs
- **Error Budget Remaining** — gauge panels per CUJ
- **p99 Latency** — stat + timeseries with per-CUJ SLO reference lines

All dashboards use the `${datasource}` template variable — never hardcoded UIDs.

## Services

| Service | Port | Purpose | OTel Annotation |
|---------|------|---------|-----------------|
| **api** | 3001 | Express REST API, Kafka producer | Yes |
| **frontend** | 80 | React SPA in nginx, proxies `/api/` to API | No (static files) |
| **inventory-svc** | 3002 | Stock reservation (simulated latency) | Yes |
| **product-worker** | - | Kafka consumer, batch product INSERT | Yes |
| **kafka** | 9092 | Bitnami Kafka (KRaft mode, no Zookeeper) | No |
| **postgres** | 5432 | PostgreSQL 16 | No |
| **k6** | - | Continuous load test traffic generator | No |

## API Endpoints

| Method | Path | CUJ | Description |
|--------|------|-----|-------------|
| `GET` | `/api/products` | product-discovery | List all products |
| `GET` | `/api/products/:id` | product-discovery | Single product |
| `GET` | `/api/products/search?q=&category=` | product-search | Search/filter products |
| `GET` | `/api/products/:id/reviews` | product-review | List reviews for a product |
| `POST` | `/api/products/:id/reviews` | product-review | Write a review |
| `POST` | `/api/orders` | checkout | Create order (transactional, calls inventory-svc) |
| `GET` | `/api/orders/:id` | order-lookup | Get order details with line items |
| `GET` | `/api/orders?email=` | order-history | Look up orders by customer email |
| `POST` | `/api/admin/upload-products` | product-upload | Bulk upload via Kafka (returns 202) |
| `GET` | `/api/admin/jobs/:id` | - | Poll async job status |
| `GET` | `/api/health` | - | Health check (DB connectivity) |

## Quick Start

### Prerequisites

- Docker Desktop (running)
- [kind](https://kind.sigs.k8s.io/), [kubectl](https://kubernetes.io/docs/tasks/tools/), [Helm](https://helm.sh/) (auto-installed by setup scripts if missing)
- Grafana Cloud account (for traces/metrics export — get credentials from grafana.com)

### 1. Create the cluster and telemetry stack

```bash
./infrastructure/scripts/setup-cluster.sh     # kind cluster + NGINX ingress
./infrastructure/scripts/setup-telemetry.sh    # cert-manager + OTel operator + collector

# Create the Grafana Cloud credentials secret
kubectl create secret generic otel-vendor-credentials \
  -n observability \
  --from-literal=GRAFANA_INSTANCE_ID=<your-instance-id> \
  --from-literal=GRAFANA_API_KEY=<your-glc-token>
```

### 2. Build, load, and deploy

```bash
./infrastructure/scripts/build-and-load.sh    # Build 4 images, load into kind, Helm upgrade
./infrastructure/scripts/deploy.sh            # First-time deploy (if not yet installed)
```

### 3. Apply Terraform SLOs and dashboards

```bash
cd terraform
terraform init
terraform plan      # Shows 16 grafana_slo + dashboard resources
terraform apply     # Creates SLOs and dashboards in Grafana Cloud
```

### 4. Open the store

Visit **http://localhost** in your browser.

- Browse products, search, write reviews, place orders
- Click **Admin** to generate and upload bulk products via Kafka
- Click **My Orders** to look up order history

### 5. (Optional) Set up Jenkins CI/CD

```bash
./infrastructure/scripts/setup-cicd.sh
```

Jenkins auto-builds on merge to main: parallel Kaniko image builds → Helm deploy → rollout verification.

### Teardown

```bash
./infrastructure/scripts/teardown.sh
```

## Traffic Generator (k6)

The Helm chart includes a k6 deployment that generates continuous load across all 8 CUJs:

| CUJ | Traffic Share |
|-----|--------------|
| product-discovery | 48% |
| checkout | 15% |
| order-lookup | 10% |
| product-search | 10% |
| product-review (read) | 7% |
| product-review (write) | 3% |
| order-history | 4% |
| product-upload | 3% |

Default: 5 RPS. Adjust live: `helm upgrade techmart ... --set traffic.rps=10`

## Directory Structure

```
api/                           Tier 2 — Express REST API + Kafka producer
  src/routes/products.js         product-discovery + product-search
  src/routes/orders.js           checkout + order-lookup + order-history
  src/routes/reviews.js          product-review
  src/routes/admin.js            product-upload (Kafka producer)
  src/tracing.js                 withJourney() + cujBaggageMiddleware
  src/db.js                      pg Pool

frontend/                      Tier 1 — React/Vite SPA
  src/components/Admin.jsx       Bulk product upload + job status
  nginx.conf                     /api/ proxy to API service

inventory-svc/                 Stock reservation microservice
product-worker/                Kafka consumer — async product batch INSERT

database/init.sql              Canonical DB schema + seed data
infrastructure/
  helm/techmart/               Helm chart (all services, Kafka, postgres, k6)
    templates/kafka/             Kafka StatefulSet (KRaft mode)
    templates/product-worker/    Worker Deployment + ConfigMap
    files/k6-test.js             Load test traffic distribution
  scripts/                     Cluster lifecycle (setup, build, deploy, teardown)
  k8s/telemetry/               OTel collector CR

terraform/
  slos.tf                      16 grafana_slo resources (2 per CUJ)
  dashboards.tf                Dashboard resources
  grafana/dashboards/          JSON dashboard definitions

ci/
  build.Jenkinsfile            Parallel Kaniko builds (4 images)
  deploy.Jenkinsfile           Helm upgrade + rollout verification
```
