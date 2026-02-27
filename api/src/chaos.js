/**
 * Chaos / fault injection engine for TechMart CUJ demos.
 *
 * In-memory config — survives for the lifetime of the process,
 * resets on pod restart (intentional for a demo tool).
 *
 * Usage from withJourney:
 *   const result = await applyChaos(cujName, fn);
 */

const { trace, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('techmart-chaos', '1.0.0');

// Map<string, { delayMs: number, errorRate: number }>
const faults = new Map();

const VALID_CUJS = new Set([
  'checkout',
  'product-discovery',
  'product-search',
  'product-review',
  'order-history',
  'order-lookup',
  'product-upload',
  'product-upload-job',
]);

function getFault(cujName) {
  return faults.get(cujName) || null;
}

function setFault(cujName, { delayMs = 0, errorRate = 0 } = {}) {
  if (!VALID_CUJS.has(cujName)) {
    throw new Error(`Unknown CUJ: ${cujName}. Valid: ${[...VALID_CUJS].join(', ')}`);
  }
  if (delayMs === 0 && errorRate === 0) {
    faults.delete(cujName);
  } else {
    faults.set(cujName, {
      delayMs:   Math.max(0, Math.floor(delayMs)),
      errorRate: Math.max(0, Math.min(1, errorRate)),
    });
  }
}

function clearFault(cujName) {
  faults.delete(cujName);
}

function clearAll() {
  faults.clear();
}

function listFaults() {
  const result = {};
  for (const [name, config] of faults) {
    result[name] = { ...config };
  }
  return result;
}

/**
 * If the CUJ has active faults, inject delay and/or errors with
 * trace-visible spans. Then call fn(). Returns fn()'s result.
 */
async function applyChaos(cujName, fn) {
  const fault = faults.get(cujName);
  if (!fault) return fn();

  const { delayMs, errorRate } = fault;

  // Delay injection — creates a visible child span
  if (delayMs > 0) {
    await tracer.startActiveSpan(
      'chaos.delay',
      {
        attributes: {
          'chaos.type':     'delay',
          'chaos.cuj':      cujName,
          'chaos.delay_ms': delayMs,
        },
      },
      async (span) => {
        await new Promise((r) => setTimeout(r, delayMs));
        span.setStatus({ code: SpanStatusCode.OK });
        span.end();
      }
    );
  }

  // Error injection — probabilistic
  if (errorRate > 0 && Math.random() < errorRate) {
    const err = new Error(`[chaos] Injected fault for CUJ '${cujName}' (errorRate=${errorRate})`);
    tracer.startActiveSpan(
      'chaos.error',
      {
        attributes: {
          'chaos.type':       'error',
          'chaos.cuj':        cujName,
          'chaos.error_rate': errorRate,
        },
      },
      (span) => {
        span.recordException(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
        span.end();
      }
    );
    throw err;
  }

  return fn();
}

module.exports = {
  VALID_CUJS,
  getFault,
  setFault,
  clearFault,
  clearAll,
  listFaults,
  applyChaos,
};
