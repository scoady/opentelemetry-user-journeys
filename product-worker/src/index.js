const { Kafka } = require('kafkajs');
const { Pool } = require('pg');
const { withJourney } = require('./tracing');
const { trace } = require('@opentelemetry/api');

const kafka = new Kafka({
  clientId: 'product-worker',
  brokers: [process.env.KAFKA_BROKER || 'kafka:9092'],
  retry: {
    initialRetryTime: 3000,
    retries: 10,
  },
});

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

const consumer = kafka.consumer({ groupId: 'product-upload-group' });

async function processMessage({ message }) {
  const payload = JSON.parse(message.value.toString());
  const { job_id, products } = payload;

  // OTel kafkajs instrumentation has already extracted trace context from
  // message headers and set it as the active context. withJourney creates
  // cuj.product-upload-job as a child of the kafka.receive span.
  await withJourney('product-upload-job', async () => {
    const span = trace.getActiveSpan();
    if (span) {
      span.setAttribute('job.id', job_id);
      span.setAttribute('job.product_count', products.length);
    }

    try {
      // Mark job as processing
      await pool.query(
        "UPDATE upload_jobs SET status = 'processing' WHERE id = $1",
        [job_id]
      );

      // Batch INSERT all products in a single multi-row statement
      const values = [];
      const params = [];
      let idx = 1;
      for (const p of products) {
        values.push(`($${idx}, $${idx + 1}, $${idx + 2}, $${idx + 3}, $${idx + 4}, $${idx + 5})`);
        params.push(p.name, p.description, p.price, p.emoji || '📦', p.category || 'Uncategorized', p.stock ?? 100);
        idx += 6;
      }

      await pool.query(
        `INSERT INTO products (name, description, price, emoji, category, stock)
         VALUES ${values.join(', ')}`,
        params
      );

      // Mark job as completed
      await pool.query(
        "UPDATE upload_jobs SET status = 'completed', processed_count = $1, completed_at = NOW() WHERE id = $2",
        [products.length, job_id]
      );

      console.log(`Job ${job_id}: inserted ${products.length} products`);
    } catch (err) {
      // Mark job as failed
      await pool.query(
        "UPDATE upload_jobs SET status = 'failed', error_message = $1, completed_at = NOW() WHERE id = $2",
        [err.message, job_id]
      ).catch(() => {}); // Don't mask the original error
      throw err; // Re-throw so withJourney records the error on the span
    }
  });
}

async function run() {
  console.log('Product worker starting...');
  await consumer.connect();
  console.log('Connected to Kafka');

  await consumer.subscribe({ topic: 'product-uploads', fromBeginning: false });
  console.log('Subscribed to product-uploads topic');

  await consumer.run({ eachMessage: processMessage });
  console.log('Product worker running — waiting for messages');
}

run().catch(err => {
  console.error('Product worker failed to start:', err);
  process.exit(1);
});
