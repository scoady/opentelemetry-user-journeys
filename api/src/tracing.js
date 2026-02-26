/**
 * Critical User Journey (CUJ) tracing helpers.
 *
 * ## Single-service usage
 *
 *   const { withJourney } = require('./tracing');
 *
 *   router.post('/', async (req, res) => {
 *     await withJourney('checkout', async () => {
 *       // ... business logic, db calls, downstream HTTP, etc.
 *     });
 *   });
 *
 * ## Cross-service usage
 *
 * In the **originating** service (e.g. the service that owns the checkout CUJ):
 *
 *   await withJourney('checkout', async () => {
 *     // Any outbound HTTP calls made here will automatically carry
 *     // baggage: cuj.name=checkout  (W3C Baggage header)
 *   });
 *
 * In every **downstream** service (inventory, payments, notifications, ...):
 *
 *   const { cujBaggageMiddleware } = require('./tracing');
 *   app.use(cujBaggageMiddleware);   // wire in early, before routes
 *
 *   // Now every request that was triggered by a CUJ will have cuj.name
 *   // stamped on its root HTTP span automatically — no other code changes.
 *
 * ## What this module does
 *
 *   withJourney(name, fn):
 *     1. Stamps cuj.name / cuj.critical on the parent HTTP span (auto-instrumented).
 *     2. Creates a child span `cuj.<name>` wrapping the critical path.
 *     3. Injects W3C Baggage entries (cuj.name, cuj.critical) into the active
 *        context so the OTel SDK propagates them in outbound request headers.
 *     4. Records exceptions and sets ERROR status automatically on failure.
 *
 *   cujBaggageMiddleware(req, res, next):
 *     1. Reads incoming W3C Baggage (already extracted by auto-instrumentation).
 *     2. Stamps cuj.name / cuj.critical on the active span for this request.
 *     — Downstream spans (pg, outbound HTTP) inherit cuj.name via the context.
 *
 * ## Querying in Grafana / Tempo
 *
 *   {span.attributes["cuj.name"] = "checkout"}          — all checkout spans
 *   {span.name = "cuj.checkout" && status = error}      — failed checkouts
 *   {span.attributes["cuj.name"] = "product-discovery"} — browse spans
 *   {span.attributes["cuj.name"] != ""}                 — any CUJ span
 */

const { trace, context, propagation, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('techmart-api', '1.0.0');

// ─────────────────────────────────────────────────────────────────────────────
// withJourney  — use in the service that *owns* a CUJ
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Wraps fn in a named CUJ span, stamps the parent HTTP span, and injects
 * W3C Baggage so all outbound calls within fn carry cuj.name automatically.
 *
 * @param {string}            name  Journey label — 'checkout', 'product-discovery', etc.
 * @param {() => Promise<T>}  fn    The critical path to instrument.
 * @returns {Promise<T>}
 */
async function withJourney(name, fn) {
  // 1. Stamp the parent HTTP span so the attribute is queryable at the root level.
  const httpSpan = trace.getActiveSpan();
  if (httpSpan) {
    httpSpan.setAttribute('cuj.name', name);
    httpSpan.setAttribute('cuj.critical', true);
  }

  // 2. Inject W3C Baggage entries into the active context.
  //    The OTel SDK propagates these as a `baggage: cuj.name=checkout,...`
  //    header on every outbound HTTP/gRPC call made within this context.
  const currentBaggage =
    propagation.getBaggage(context.active()) ?? propagation.createBaggage();
  const baggageWithCuj = currentBaggage
    .setEntry('cuj.name',     { value: name   })
    .setEntry('cuj.critical', { value: 'true' });
  const ctxWithBaggage = propagation.setBaggage(context.active(), baggageWithCuj);

  // 3. Run everything inside a context that carries the enriched baggage AND
  //    a named child span wrapping the critical path.
  return context.with(ctxWithBaggage, () =>
    tracer.startActiveSpan(
      `cuj.${name}`,
      { attributes: { 'cuj.name': name, 'cuj.critical': true } },
      async (span) => {
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
      }
    )
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// cujBaggageMiddleware  — use in *downstream* services
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Express middleware that reads any incoming W3C Baggage extracted by the
 * OTel SDK and stamps cuj.name / cuj.critical onto the active span.
 *
 * Wire this in early (before routes) in any service that participates in a CUJ
 * but does not call withJourney itself:
 *
 *   const { cujBaggageMiddleware } = require('./tracing');
 *   app.use(cujBaggageMiddleware);
 *
 * The auto-instrumentation init-container extracts the `baggage` header and
 * places the entries into the active context before this middleware runs, so
 * no manual header parsing is required.
 */
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

module.exports = { withJourney, cujBaggageMiddleware };
