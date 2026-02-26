/**
 * Critical User Journey (CUJ) tracing helpers.
 *
 * Usage:
 *   const { withJourney } = require('./tracing');
 *
 *   router.post('/', async (req, res) => {
 *     await withJourney('checkout', async () => {
 *       // ... all your business logic, db calls, etc.
 *     });
 *   });
 *
 * What this does:
 *   1. Stamps cuj.name on the current active span (the HTTP span created by
 *      auto-instrumentation), so top-level HTTP spans are queryable by journey.
 *   2. Creates a child span named `cuj.<name>` that wraps the critical path.
 *      All downstream spans (pg queries etc.) become children of this span.
 *   3. Records exceptions and sets ERROR status automatically on failure.
 *
 * Querying in Grafana/Tempo:
 *   {span.attributes["cuj.name"] = "checkout"}          — all checkout spans
 *   {span.name = "cuj.checkout" && status = error}      — failed checkouts
 *   {span.attributes["cuj.name"] = "product-discovery"} — browse spans
 */

const { trace, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('techmart-api', '1.0.0');

/**
 * Wraps fn in a named CUJ span and stamps the attribute on the parent HTTP span.
 *
 * @param {string}            name  Journey label — 'checkout', 'product-discovery', etc.
 * @param {() => Promise<T>}  fn    The critical path to instrument.
 * @returns {Promise<T>}
 */
async function withJourney(name, fn) {
  // Stamp the parent HTTP span so the attribute is queryable at the root level.
  const httpSpan = trace.getActiveSpan();
  if (httpSpan) {
    httpSpan.setAttribute('cuj.name', name);
    httpSpan.setAttribute('cuj.critical', true);
  }

  // Create a named child span that wraps the business logic.
  // All downstream db/http spans become children of this span.
  return tracer.startActiveSpan(
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
  );
}

module.exports = { withJourney };
