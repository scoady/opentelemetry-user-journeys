/**
 * CUJ tracing helpers — identical to api/src/tracing.js.
 *
 * In this service we only use cujBaggageMiddleware: the Baggage header
 * injected by the checkout service (via withJourney) is extracted by the
 * OTel SDK init container and placed into the active context before any
 * route handler runs. The middleware reads it and stamps cuj.name onto
 * this service's spans so spanmetrics can attribute them to the CUJ.
 */

const { trace, context, propagation, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('inventory-svc', '1.0.0');

async function withJourney(name, fn) {
  const httpSpan = trace.getActiveSpan();
  if (httpSpan) {
    httpSpan.setAttribute('cuj.name', name);
    httpSpan.setAttribute('cuj.critical', true);
  }

  const currentBaggage =
    propagation.getBaggage(context.active()) ?? propagation.createBaggage();
  const baggageWithCuj = currentBaggage
    .setEntry('cuj.name',     { value: name   })
    .setEntry('cuj.critical', { value: 'true' });
  const ctxWithBaggage = propagation.setBaggage(context.active(), baggageWithCuj);

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
