/**
 * CUJ tracing helpers for product-worker.
 *
 * The worker uses withJourney to wrap Kafka message processing in a
 * cuj.product-upload-job span. The OTel SDK (injected by the operator)
 * auto-instruments kafkajs, extracting trace context from message headers
 * so the worker's spans appear as children of the producer's trace.
 */

const { trace, context, propagation, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('product-worker', '1.0.0');

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

module.exports = { withJourney };
