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

module.exports = router;
