const express = require('express');
const router = express.Router();
const db = require('../db');
const { trace } = require('@opentelemetry/api');
const { withJourney } = require('../tracing');

// GET /api/products/search?q=term&category=cat          CUJ: product-search
router.get('/search', async (req, res) => {
  try {
    const rows = await withJourney('product-search', async () => {
      const { q, category } = req.query;
      const conditions = [];
      const params = [];
      let idx = 1;

      if (q) {
        conditions.push(`(name ILIKE $${idx} OR description ILIKE $${idx})`);
        params.push(`%${q}%`);
        idx++;
      }
      if (category) {
        conditions.push(`category = $${idx}`);
        params.push(category);
        idx++;
      }

      const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
      const result = await db.query(
        `SELECT id, name, description, price, emoji, category, stock FROM products ${where} ORDER BY id`,
        params
      );

      const span = trace.getActiveSpan();
      if (span) {
        span.setAttribute('search.query', q || '');
        span.setAttribute('search.category', category || '');
        span.setAttribute('search.results_count', result.rows.length);
      }

      return result.rows;
    });
    res.json(rows);
  } catch (err) {
    console.error('Error searching products:', err);
    res.status(500).json({ error: 'Failed to search products' });
  }
});

// GET /api/products                                    CUJ: product-discovery
router.get('/', async (req, res) => {
  try {
    const rows = await withJourney('product-discovery', async () => {
      const result = await db.query(
        'SELECT id, name, description, price, emoji, category, stock FROM products ORDER BY id'
      );
      return result.rows;
    });
    res.json(rows);
  } catch (err) {
    console.error('Error fetching products:', err);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

// GET /api/products/:id                                CUJ: product-discovery
router.get('/:id', async (req, res) => {
  try {
    const row = await withJourney('product-discovery', async () => {
      const { id } = req.params;
      const result = await db.query(
        'SELECT id, name, description, price, emoji, category, stock FROM products WHERE id = $1',
        [id]
      );
      if (result.rows.length === 0) {
        const err = new Error('Product not found');
        err.status = 404;
        throw err;
      }
      return result.rows[0];
    });
    res.json(row);
  } catch (err) {
    console.error('Error fetching product:', err);
    const status = err.status || 500;
    res.status(status).json({ error: err.message || 'Failed to fetch product' });
  }
});

module.exports = router;
