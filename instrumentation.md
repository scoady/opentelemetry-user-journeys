# TechMart Instrumentation

An end-to-end guide to how observability is wired in this project — from
auto-instrumentation through the collector to Grafana Cloud — with focus on
the **Critical User Journey (CUJ)** pattern and the SLO metrics it enables.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Signal Pipeline](#signal-pipeline)
3. [Auto-Instrumentation](#auto-instrumentation)
4. [Critical User Journeys](#critical-user-journeys)
5. [Cross-Service Propagation](#cross-service-propagation)
6. [Span Anatomy](#span-anatomy)
7. [Collector: spanmetrics](#collector-spanmetrics)
8. [SLO Metrics Reference](#slo-metrics-reference)
9. [Grafana Dashboards](#grafana-dashboards)
10. [Adding a New CUJ](#adding-a-new-cuj)

---

## Architecture Overview

```
┌─────────────────────── kind cluster ───────────────────────────────┐
│                                                                     │
│  webstore namespace                                                 │
│  ┌──────────────┐   ┌──────────────────────────────────────────┐   │
│  │   frontend   │   │                  api                     │   │
│  │  nginx+React │──▶│  Express · Node.js                       │   │
│  └──────────────┘   │  ┌────────────────────────────────────┐  │   │
│                     │  │  OTel SDK (auto-injected init ctr)  │  │   │
│                     │  │  traces · metrics · logs            │  │   │
│                     │  └───────────────┬────────────────────┘  │   │
│                     └──────────────────┼─────────────────────┘  │  │
│                                        │ OTLP/HTTP :4318         │  │
│  observability namespace               ▼                         │  │
│  ┌─────────────────────────────────────────────────────────┐    │  │
│  │                  OTel Collector                         │    │  │
│  │  receivers:  otlp (gRPC :4317, HTTP :4318)              │    │  │
│  │  processors: batch                                      │    │  │
│  │  connectors: spanmetrics ──────────────────────────┐   │    │  │
│  │  exporters:  otlp_http/grafana  basicauth/grafana   │   │    │  │
│  └─────────────────────────────────────────────┬───────┘   │   │  │
│                                                │            │   │  │
└────────────────────────────────────────────────┼────────────┼───┘  │
                                                 │            │
                         OTLP/HTTP (traces+logs) │            │ OTLP/HTTP (metrics)
                                                 ▼            ▼
                              ┌─────── Grafana Cloud ──────────┐
                              │  Tempo (traces)                │
                              │  Mimir/Prometheus (metrics)    │
                              │  Loki (logs)                   │
                              └────────────────────────────────┘
```

---

## Signal Pipeline

Three signals flow through the same collector, each on its own pipeline.
The spanmetrics **connector** bridges traces into the metrics pipeline,
generating RED metrics without any SDK changes.

```
TRACES  ──▶ [batch] ──▶ otlp_http/grafana (Tempo)
                  └────▶ spanmetrics ─────────────┐
                                                   │ (connector)
METRICS ◀──────────────────────────────────────────┘
        ──▶ [batch] ──▶ otlp_http/grafana (Mimir)

LOGS    ──▶ [batch] ──▶ otlp_http/grafana (Loki)
```

| Signal  | Source                          | Destination     |
|---------|---------------------------------|-----------------|
| Traces  | OTel Node.js SDK (auto)         | Grafana Tempo   |
| Metrics | SDK + spanmetrics connector     | Grafana Mimir   |
| Logs    | Console bridge (auto)           | Grafana Loki    |

---

## Auto-Instrumentation

The **OpenTelemetry Operator** injects the Node.js SDK into every API pod
at startup — no changes to `package.json` or application boot code required.

### How injection works

```
Pod scheduled
     │
     ▼
Init container runs (opentelemetry-auto-instrumentation-nodejs)
     │  copies SDK to /otel-auto-instrumentation-nodejs/
     ▼
API container starts with:
  NODE_OPTIONS=--require /otel-auto-instrumentation-nodejs/autoinstrumentation.js
  OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc.cluster.local:4318
  OTEL_SERVICE_NAME=api
  OTEL_METRICS_EXPORTER=otlp
  OTEL_LOGS_EXPORTER=otlp
  OTEL_METRIC_EXPORT_INTERVAL=60000   ← 60s to keep cardinality low
```

The `Instrumentation` CR in `infrastructure/k8s/telemetry/instrumentation.yaml`
drives this configuration. The deployment opt-in is a single pod annotation:

```yaml
# infrastructure/k8s/api/deployment.yaml
annotations:
  instrumentation.opentelemetry.io/inject-nodejs: "true"
```

### What the SDK instruments automatically

| Library      | Span type        | Key attributes captured                                 |
|--------------|------------------|---------------------------------------------------------|
| `http`       | Server / client  | `http.method`, `http.route`, `http.status_code`, url    |
| `express`    | Middleware/route | `express.name`, `express.type`, `http.route`            |
| `pg`         | DB query         | `db.statement`, `db.name`, `net.peer.name`              |
| `pg-pool`    | Pool connect     | `db.postgresql.idle.timeout.millis`                     |
| Node runtime | Metrics          | V8 heap spaces, GC duration, event loop utilisation     |
| Console      | Logs             | Bridged to OTLP log records with trace correlation      |

---

## Critical User Journeys

A **Critical User Journey** is a named, semantically meaningful path through
the system that directly maps to business value. We instrument them with a
lightweight helper in `api/src/tracing.js`.

### Defined journeys

| Journey name          | Trigger                  | Business meaning                          |
|-----------------------|--------------------------|-------------------------------------------|
| `checkout`            | `POST /api/orders`       | User completes a purchase transaction     |
| `product-discovery`   | `GET  /api/products[/*]` | User browses the product catalogue        |
| `order-lookup`        | `GET  /api/orders/:id`   | User views an existing order              |

### The `withJourney` helper

```js
// api/src/tracing.js
const { trace, context, propagation, SpanStatusCode } = require('@opentelemetry/api');
const tracer = trace.getTracer('techmart-api', '1.0.0');

async function withJourney(name, fn) {
  // 1. Stamp cuj.name on the parent HTTP span (created by auto-instrumentation).
  const httpSpan = trace.getActiveSpan();
  if (httpSpan) {
    httpSpan.setAttribute('cuj.name', name);
    httpSpan.setAttribute('cuj.critical', true);
  }

  // 2. Inject W3C Baggage — SDK propagates these as a `baggage` header on every
  //    outbound HTTP call within fn(), letting downstream services read cuj.name.
  const currentBaggage =
    propagation.getBaggage(context.active()) ?? propagation.createBaggage();
  const baggageWithCuj = currentBaggage
    .setEntry('cuj.name',     { value: name   })
    .setEntry('cuj.critical', { value: 'true' });
  const ctxWithBaggage = propagation.setBaggage(context.active(), baggageWithCuj);

  // 3. Run everything inside a context that carries both the enriched baggage
  //    and a named child span wrapping the critical path.
  return context.with(ctxWithBaggage, () =>
    tracer.startActiveSpan(`cuj.${name}`, { attributes: {
      'cuj.name': name,
      'cuj.critical': true,
    }}, async (span) => {
      try {
        const result = await fn();
        span.setStatus({ code: SpanStatusCode.OK });
        return result;
      } catch (err) {
        span.recordException(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
        throw err;
      } finally {
        span.end();
      }
    })
  );
}
```

**Usage in a route handler:**

```js
// api/src/routes/orders.js
router.post('/', async (req, res) => {
  const client = await db.connect();
  try {
    const order = await withJourney('checkout', async () => {
      // every db call here becomes a child of cuj.checkout
      await client.query('BEGIN');
      // ... validate stock, insert order, decrement stock ...
      await client.query('COMMIT');
      return orderRow;
    });
    res.status(201).json(order);
  } catch (err) {
    await client.query('ROLLBACK');
    res.status(400).json({ error: err.message });
  }
});
```

---

## Cross-Service Propagation

When a CUJ spans multiple services (e.g. checkout calls an inventory service
and a payments service), `cuj.name` needs to appear on spans in *all* of them
so SLO dashboards and traces tell a coherent story.

### How it works

```
 api (checkout)              inventory-svc               payments-svc
 ──────────────              ─────────────               ────────────
 withJourney('checkout')
   │  sets W3C Baggage:
   │  cuj.name=checkout
   │
   ├──▶ HTTP POST /reserve ──────────────────────────▶
   │     headers: baggage: cuj.name=checkout, …        cujBaggageMiddleware
   │                                                     reads baggage entry
   │                                                     stamps cuj.name on
   │                                                     this service's spans
   │
   └──▶ HTTP POST /charge ───────────────────────────────────────────▶
         headers: baggage: cuj.name=checkout, …                    cujBaggageMiddleware
                                                                     same stamping
```

**Key properties:**
- The `baggage` HTTP header is injected automatically by the OTel SDK — no
  manual header code in the originating service.
- Auto-instrumentation extracts the `baggage` header in the receiving service
  *before* any route handler runs, so the values are already in the active
  context when `cujBaggageMiddleware` reads them.
- If a downstream service also calls `withJourney()` for its own sub-journeys,
  the baggage is already set — `setEntry` overwrites cleanly.

### The `cujBaggageMiddleware`

Register this in every service that participates in a CUJ but does not
*originate* one:

```js
// In any downstream service's entry point (e.g. server.js / index.js)
const { cujBaggageMiddleware } = require('./tracing');
app.use(cujBaggageMiddleware);   // before routes — after body parsing
```

Implementation (already in `api/src/tracing.js` and wired into `api/src/index.js`):

```js
function cujBaggageMiddleware(req, res, next) {
  const baggage = propagation.getBaggage(context.active());
  if (baggage) {
    const cujEntry = baggage.getEntry('cuj.name');
    if (cujEntry) {
      const span = trace.getActiveSpan();
      if (span) {
        span.setAttribute('cuj.name',     cujEntry.value);
        span.setAttribute('cuj.critical', true);
      }
    }
  }
  next();
}
```

### Propagators

The `Instrumentation` CR enables both required propagators:

```yaml
# infrastructure/k8s/telemetry/instrumentation.yaml
spec:
  propagators:
    - tracecontext   # W3C Trace Context  (traceparent / tracestate headers)
    - baggage        # W3C Baggage        (baggage header — carries cuj.name)
```

`tracecontext` stitches spans from different services into one trace tree in
Tempo. `baggage` carries the semantic `cuj.name` label through the call graph.

### Result in Grafana

Every span in the call chain — regardless of which service emitted it —
carries `cuj.name`. The spanmetrics connector therefore emits
`techmart_calls_total{cuj_name="checkout"}` for inventory and payments spans
too, so a single PromQL query covers the **total cost** of the journey across
all services:

```promql
# Error rate across ALL services participating in the checkout CUJ
100 * sum(rate(techmart_calls_total{cuj_name="checkout", status_code="STATUS_CODE_ERROR"}[5m]))
    / sum(rate(techmart_calls_total{cuj_name="checkout"}[5m]))
```

---

## Span Anatomy

A successful checkout request produces this trace tree (single-service view).

```
POST /api/orders                              ← HTTP span (auto · http instrumentation)
│  cuj.name = "checkout"                        ← stamped by withJourney on httpSpan
│  http.route = "/api/orders"
│  http.method = "POST"
│  http.status_code = 201
│
└── cuj.checkout                             ← named CUJ span (manual · tracing.js)
    │  cuj.name = "checkout"
    │  cuj.critical = true
    │  status = OK
    │
    ├── pg-pool.connect                      ─┐
    ├── pg.query:BEGIN                        │
    ├── pg.query:SELECT products              │ auto-instrumented by
    ├── pg.query:INSERT orders                │ @opentelemetry/instrumentation-pg
    ├── pg.query:INSERT order_items           │
    ├── pg.query:UPDATE products (stock)      │
    └── pg.query:COMMIT                      ─┘
```

With cross-service propagation the same trace continues into downstream services:

```
POST /api/orders
└── cuj.checkout  [api]                      baggage: cuj.name=checkout ──▶
    ├── pg.query:* (stock check)
    │
    ├── POST /reserve  [inventory-svc]        ← new remote span, same trace
    │   │  cuj.name = "checkout"               ← stamped by cujBaggageMiddleware
    │   └── pg.query:UPDATE stock
    │
    └── POST /charge   [payments-svc]         ← another remote span
        │  cuj.name = "checkout"               ← stamped by cujBaggageMiddleware
        └── http.client:stripe-api
```

A failed checkout (e.g. out of stock) looks like:

```
POST /api/orders                              http.status_code = 400
│  cuj.name = "checkout"
│
└── cuj.checkout                             status = ERROR
    │  cuj.name = "checkout"                 exception.message = "Insufficient stock …"
    │
    ├── pg-pool.connect
    ├── pg.query:BEGIN
    └── pg.query:SELECT products             ← query ran; error thrown in JS, not SQL
```

The span status `ERROR` is what the spanmetrics connector counts as a failure,
and what SLO dashboards surface as the error rate.

---

## Collector: spanmetrics

The `spanmetrics` connector derives **RED metrics** (Rate, Errors, Duration)
from every span that passes through the traces pipeline. This means SLO
metrics are always consistent with what you see in Tempo — they come from
the same data source.

### Configuration (`infrastructure/k8s/telemetry/collector/collector.yaml`)

```yaml
connectors:
  spanmetrics:
    namespace: techmart              # metric name prefix
    histogram:
      explicit:
        buckets: [10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2s, 5s, 10s]
    dimensions:
      - name: cuj.name              # → label cuj_name on every metric
      - name: http.route
      - name: http.request.method
      - name: http.response.status_code
    metrics_flush_interval: 60s

service:
  pipelines:
    traces:
      exporters: [debug, otlp_http/grafana, spanmetrics]  # ← feeds the connector
    metrics:
      receivers: [otlp, spanmetrics]                       # ← connector output lands here
```

### Generated metrics

| Metric (Prometheus name)                      | Type      | Description                        |
|-----------------------------------------------|-----------|------------------------------------|
| `techmart_calls_total`                        | Counter   | Number of spans by name and status |
| `techmart_duration_milliseconds_bucket`       | Histogram | Span duration distribution         |
| `techmart_duration_milliseconds_count`        | Counter   | Total span count (histogram count) |
| `techmart_duration_milliseconds_sum`          | Counter   | Total span duration in ms          |

### Key labels

| Label                     | Example values                                        |
|---------------------------|-------------------------------------------------------|
| `span_name`               | `cuj.checkout`, `cuj.product-discovery`, `GET /api/…` |
| `status_code`             | `STATUS_CODE_OK`, `STATUS_CODE_ERROR`, `STATUS_CODE_UNSET` |
| `cuj_name`                | `checkout`, `product-discovery`, `order-lookup`       |
| `service_name`            | `api`                                                 |
| `http_route`              | `/api/orders`, `/api/products`                        |
| `http_request_method`     | `GET`, `POST`                                         |
| `http_response_status_code` | `200`, `201`, `400`, `500`                          |

---

## SLO Metrics Reference

These PromQL expressions power the Grafana dashboards.

### Success rate (availability SLO)

```promql
# 1h window — % of checkout spans that did not error
100 * sum(increase(techmart_calls_total{
    span_name="cuj.checkout",
    status_code!="STATUS_CODE_ERROR"
}[1h]))
/ sum(increase(techmart_calls_total{span_name="cuj.checkout"}[1h]))
```

### Error budget remaining (30-day window, 99.9% SLO)

```promql
# Approaches 0% as you consume the allowed 0.1% error budget
100 * (
  1 - (
    sum(increase(techmart_calls_total{
        span_name="cuj.checkout",
        status_code="STATUS_CODE_ERROR"
    }[30d]))
    / sum(increase(techmart_calls_total{span_name="cuj.checkout"}[30d]))
  ) / 0.001          ← error budget fraction (1 - 0.999)
)
```

### p99 latency

```promql
histogram_quantile(0.99,
  sum(rate(techmart_duration_milliseconds_bucket{
      span_name="cuj.checkout"
  }[5m])) by (le)
)
```

### Error rate (5m rate — for alerting)

```promql
sum(rate(techmart_calls_total{
    span_name="cuj.checkout",
    status_code="STATUS_CODE_ERROR"
}[5m]))
/ sum(rate(techmart_calls_total{span_name="cuj.checkout"}[5m]))
```

### Substituting journeys

Replace `span_name="cuj.checkout"` with any of:

| Journey               | `span_name` value           |
|-----------------------|-----------------------------|
| Checkout              | `cuj.checkout`              |
| Product discovery     | `cuj.product-discovery`     |
| Order lookup          | `cuj.order-lookup`          |
| All CUJs combined     | `span_name=~"cuj\\..*"`     |

---

## Grafana Dashboards

Two importable JSON dashboards are in `infrastructure/grafana/dashboards/`.

**Import:** Grafana → Dashboards → Import → Upload JSON → map `DS_PROMETHEUS`
to your Grafana Cloud Mimir data source.

### `slo-overview.json`

One row per CUJ, each showing:

```
┌──────────────────────────────────────────────────────────────────────┐
│  checkout  (POST /api/orders)                                        │
├─────────────────┬─────────────────┬─────────────┬────────────────────┤
│  Success Rate   │  p99 Latency    │ Req Rate    │ Error Rate (chart) │
│  99.97%  🟢     │  143ms   🟢     │ 1.2 req/s   │ vs 0.1% target ── │
└─────────────────┴─────────────────┴─────────────┴────────────────────┘
```

### `checkout-slo.json`

Deep-dive on the checkout journey with a `$window` variable (1h → 30d):

```
┌──────────────┬────────────────────┬──────────┬────────┬────────┬────────┐
│ Success Rate │ Error Budget (30d) │  p99     │  RPS   │ Errors │ Total  │
│  99.970%  🟢 │  [███████░░░] 70%  │  143ms   │ 1.2/s  │   3    │ 10 421 │
└──────────────┴────────────────────┴──────────┴────────┴────────┴────────┘

Error Rate vs SLO Target        Latency Percentiles
┌────────────────────────┐      ┌────────────────────────┐
│  0.1% ╌╌╌╌╌╌╌╌╌╌╌╌╌╌  │      │ 2000ms ╌╌╌╌╌╌╌╌╌╌╌╌╌╌  │
│       ╱╲               │      │        p99 ────         │
│  0%  ─────────────     │      │        p95 ────         │
└────────────────────────┘      │        p50 ────         │
                                └────────────────────────┘

Request Volume (stacked by status)
┌──────────────────────────────────────────────────────────────────┐
│ █████████████████████████ STATUS_CODE_OK      ████████████████   │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░ STATUS_CODE_UNSET   ░░░░░░░░░░░░░░░░   │
│ ▒ STATUS_CODE_ERROR                                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Adding a New CUJ

### Single-service CUJ (3 steps)

**1. Wrap the critical logic in `withJourney`:**

```js
const { withJourney } = require('../tracing');

router.post('/checkout/express', async (req, res) => {
  try {
    const result = await withJourney('express-checkout', async () => {
      // your critical business logic here
    });
    res.status(201).json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});
```

**2. The collector picks it up automatically.**
`spanmetrics` will start emitting `techmart_calls_total{span_name="cuj.express-checkout"}`
within one flush interval (60s). No collector config changes needed.

**3. Query it immediately:**

```promql
# Success rate
100 * sum(increase(techmart_calls_total{span_name="cuj.express-checkout", status_code!="STATUS_CODE_ERROR"}[1h]))
    / sum(increase(techmart_calls_total{span_name="cuj.express-checkout"}[1h]))

# p99 latency
histogram_quantile(0.99, sum(rate(techmart_duration_milliseconds_bucket{span_name="cuj.express-checkout"}[5m])) by (le))
```

Add a row to the SLO overview dashboard by duplicating any existing row and
substituting the `span_name` filter.

### Cross-service CUJ (1 extra step per downstream service)

If the journey makes outbound calls to other services, add `cujBaggageMiddleware`
to each of those services:

```js
// In every participating downstream service (inventory-svc, payments-svc, …)
const { cujBaggageMiddleware } = require('./tracing');   // copy tracing.js there
app.use(cujBaggageMiddleware);
```

No other changes are needed — `withJourney` already sets the baggage, and the
OTel SDK already propagates it via the `baggage` HTTP header.

---

## File Reference

| Path                                                          | Purpose                                                               |
|---------------------------------------------------------------|-----------------------------------------------------------------------|
| `api/src/tracing.js`                                          | `withJourney()` + `cujBaggageMiddleware` — CUJ helpers                |
| `api/src/index.js`                                            | Wires `cujBaggageMiddleware` early in the Express stack               |
| `api/src/routes/orders.js`                                    | `checkout`, `order-lookup` journeys                                   |
| `api/src/routes/products.js`                                  | `product-discovery` journey                                           |
| `infrastructure/k8s/telemetry/instrumentation.yaml`           | OTel Operator `Instrumentation` CR (SDK config)      |
| `infrastructure/k8s/telemetry/collector/collector.yaml`       | Collector config incl. spanmetrics connector         |
| `infrastructure/k8s/telemetry/collector/secret.yaml`          | Secret template (credentials never committed)        |
| `infrastructure/helm/cert-manager/values.yaml`                | cert-manager Helm values                             |
| `infrastructure/helm/opentelemetry-operator/values.yaml`      | OTel Operator Helm values                            |
| `infrastructure/scripts/setup-telemetry.sh`                   | One-shot install: cert-manager + operator + CR       |
| `infrastructure/grafana/dashboards/slo-overview.json`         | All-CUJ SLO overview dashboard                       |
| `infrastructure/grafana/dashboards/checkout-slo.json`         | Checkout deep-dive with error budget gauge           |
