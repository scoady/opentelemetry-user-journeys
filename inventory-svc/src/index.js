/**
 * inventory-svc — stock reservation endpoint for the TechMart checkout CUJ.
 *
 * Deliberately simple: validates items, sleeps for ARTIFICIAL_DELAY_MS to
 * simulate a slow inventory DB lookup, then returns a reservation confirmation.
 *
 * The OTel init container (injected by the Operator) instruments this service
 * automatically. cujBaggageMiddleware reads the incoming W3C Baggage header
 * and stamps cuj.name onto every span, so spanmetrics can attribute this
 * service's latency to the checkout CUJ.
 *
 * Change the delay live without redeploying:
 *   helm upgrade techmart ./infrastructure/helm/techmart \
 *     --namespace webstore --reuse-values \
 *     --set inventorySvc.artificialDelayMs=1500
 */

const express = require('express');
const { cujBaggageMiddleware } = require('./tracing');

const app  = express();
const PORT = parseInt(process.env.PORT || '3002');

// Configurable delay — simulates an inventory DB that can be fast or slow.
const DELAY_MS = parseInt(process.env.ARTIFICIAL_DELAY_MS || '500');

app.use(express.json());

// Reads incoming W3C Baggage and stamps cuj.name on this request's span.
// Must come before routes so the label is set before any child spans are created.
app.use(cujBaggageMiddleware);

// POST /reserve
// Body: { items: [{ product_id: number, quantity: number }] }
// Returns: { reserved: true, items: [...], delay_ms: number }
app.post('/reserve', async (req, res) => {
  const { items } = req.body;

  if (!items || items.length === 0) {
    return res.status(400).json({ error: 'items is required' });
  }

  // Simulate inventory system latency (DB lookup, distributed lock, etc.)
  if (DELAY_MS > 0) {
    await new Promise(r => setTimeout(r, DELAY_MS));
  }

  res.json({
    reserved: true,
    items: items.map(i => ({ ...i, reserved: true })),
    delay_ms: DELAY_MS,
  });
});

app.get('/health', (req, res) => res.json({ status: 'ok', delay_ms: DELAY_MS }));

app.use((req, res) => res.status(404).json({ error: `${req.path} not found` }));

app.listen(PORT, () =>
  console.log(`inventory-svc running on port ${PORT} (artificial delay: ${DELAY_MS}ms)`)
);
