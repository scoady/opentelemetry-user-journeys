const express = require('express');
const cors = require('cors');
const db = require('./db');
const { cujBaggageMiddleware } = require('./tracing');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json());

// Propagate incoming W3C Baggage (cuj.name, cuj.critical) onto the active span
// so every request that was triggered as part of a CUJ carries the label,
// even when this service doesn't call withJourney() itself.
app.use(cujBaggageMiddleware);

// Routes
app.use('/api/products', require('./routes/products'));
app.use('/api/orders', require('./routes/orders'));

// Health check
app.get('/api/health', async (req, res) => {
  try {
    await db.query('SELECT 1');
    res.json({ status: 'ok', db: 'connected' });
  } catch (err) {
    res.status(503).json({ status: 'error', db: 'disconnected', message: err.message });
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.path} not found` });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`TechMart API running on port ${PORT}`);
});
