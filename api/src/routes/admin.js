const express = require('express');
const router = express.Router();
const { Kafka } = require('kafkajs');
const db = require('../db');
const { trace } = require('@opentelemetry/api');
const { withJourney } = require('../tracing');

const kafka = new Kafka({
  clientId: 'techmart-api',
  brokers: [process.env.KAFKA_BROKER || 'kafka:9092'],
});
const producer = kafka.producer();
let producerConnected = false;

async function ensureProducer() {
  if (!producerConnected) {
    await producer.connect();
    producerConnected = true;
  }
}

// POST /api/admin/upload-products — CUJ: product-upload
router.post('/upload-products', async (req, res) => {
  const { products } = req.body;

  if (!products || !Array.isArray(products) || products.length === 0) {
    return res.status(400).json({ error: 'products array is required and must not be empty' });
  }

  try {
    const result = await withJourney('product-upload', async () => {
      const span = trace.getActiveSpan();
      const traceId = span?.spanContext()?.traceId || '';

      // Create upload_jobs record
      const jobResult = await db.query(
        `INSERT INTO upload_jobs (status, total_products, trace_id)
         VALUES ('pending', $1, $2) RETURNING id, status, total_products, trace_id, created_at`,
        [products.length, traceId]
      );
      const job = jobResult.rows[0];

      if (span) {
        span.setAttribute('job.id', job.id);
        span.setAttribute('job.product_count', products.length);
      }

      // Produce to Kafka (within withJourney context so kafkajs
      // auto-instrumentation injects traceparent + baggage into
      // message headers automatically)
      await ensureProducer();
      await producer.send({
        topic: 'product-uploads',
        messages: [{
          key: String(job.id),
          value: JSON.stringify({ job_id: job.id, products }),
        }],
      });

      return {
        job_id: job.id,
        trace_id: traceId,
        status: 'pending',
        total_products: products.length,
      };
    });

    res.status(202).json(result);
  } catch (err) {
    console.error('Error creating upload job:', err);
    res.status(500).json({ error: err.message || 'Failed to create upload job' });
  }
});

// GET /api/admin/jobs/:id — poll job status (not a CUJ)
router.get('/jobs/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await db.query(
      'SELECT id, status, total_products, processed_count, error_message, trace_id, created_at, completed_at FROM upload_jobs WHERE id = $1',
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Job not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error fetching job:', err);
    res.status(500).json({ error: 'Failed to fetch job status' });
  }
});

// ── Chaos / fault injection endpoints ────────────────────────────────────────
const http = require('http');
const chaos = require('../chaos');

const INVENTORY_URL = process.env.INVENTORY_URL || 'http://inventory-svc:3002';

// Inventory-delay proxy routes MUST come before the parameterized :cuj routes,
// otherwise Express matches :cuj = "inventory-delay".

// GET /api/admin/chaos/inventory-delay — read current inventory-svc delay
router.get('/chaos/inventory-delay', (req, res) => {
  const url = new URL('/admin/delay', INVENTORY_URL);
  http.get({ hostname: url.hostname, port: url.port || 80, path: url.pathname }, (proxyRes) => {
    let data = '';
    proxyRes.on('data', chunk => data += chunk);
    proxyRes.on('end', () => {
      try { res.status(proxyRes.statusCode).json(JSON.parse(data)); }
      catch { res.status(502).json({ error: 'Bad response from inventory-svc' }); }
    });
  }).on('error', (err) => {
    res.status(502).json({ error: `inventory-svc unreachable: ${err.message}` });
  });
});

// PUT /api/admin/chaos/inventory-delay — set inventory-svc delay
router.put('/chaos/inventory-delay', (req, res) => {
  const { delayMs } = req.body;
  if (typeof delayMs !== 'number' || delayMs < 0) {
    return res.status(400).json({ error: 'delayMs must be a non-negative number' });
  }

  const body = Buffer.from(JSON.stringify({ delayMs }));
  const url  = new URL('/admin/delay', INVENTORY_URL);

  const proxyReq = http.request({
    hostname: url.hostname,
    port:     url.port || 80,
    path:     url.pathname,
    method:   'PUT',
    headers: { 'Content-Type': 'application/json', 'Content-Length': body.length },
  }, (proxyRes) => {
    let data = '';
    proxyRes.on('data', chunk => data += chunk);
    proxyRes.on('end', () => {
      try { res.status(proxyRes.statusCode).json(JSON.parse(data)); }
      catch { res.status(502).json({ error: 'Bad response from inventory-svc' }); }
    });
  });

  proxyReq.on('error', (err) => {
    res.status(502).json({ error: `inventory-svc unreachable: ${err.message}` });
  });
  proxyReq.write(body);
  proxyReq.end();
});

// GET /api/admin/chaos — list all active faults
router.get('/chaos', (req, res) => {
  res.json({ faults: chaos.listFaults(), validCujs: [...chaos.VALID_CUJS] });
});

// PUT /api/admin/chaos/:cuj — set fault for a CUJ
router.put('/chaos/:cuj', (req, res) => {
  try {
    const { delayMs = 0, errorRate = 0 } = req.body;
    chaos.setFault(req.params.cuj, { delayMs, errorRate });
    res.json({ cuj: req.params.cuj, ...chaos.getFault(req.params.cuj) });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// DELETE /api/admin/chaos/:cuj — clear fault for a CUJ
router.delete('/chaos/:cuj', (req, res) => {
  chaos.clearFault(req.params.cuj);
  res.json({ cleared: req.params.cuj });
});

// DELETE /api/admin/chaos — clear ALL faults
router.delete('/chaos', (req, res) => {
  chaos.clearAll();
  res.json({ cleared: 'all' });
});

// GET /api/admin/config — frontend config (e.g. Grafana embed URL)
router.get('/config', (req, res) => {
  res.json({
    grafanaEmbedUrl: process.env.GRAFANA_EMBED_URL || '',
  });
});

module.exports = router;
