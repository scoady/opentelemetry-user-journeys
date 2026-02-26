const express = require('express');
const router = express.Router({ mergeParams: true });
const db = require('../db');
const { trace } = require('@opentelemetry/api');
const { withJourney } = require('../tracing');

// GET /api/products/:productId/reviews                  CUJ: product-review
router.get('/', async (req, res) => {
  try {
    const rows = await withJourney('product-review', async () => {
      const { productId } = req.params;
      const result = await db.query(
        'SELECT id, product_id, rating, reviewer_name, comment, created_at FROM reviews WHERE product_id = $1 ORDER BY created_at DESC',
        [productId]
      );

      const span = trace.getActiveSpan();
      if (span) {
        span.setAttribute('review.product_id', parseInt(productId));
        span.setAttribute('review.results_count', result.rows.length);
      }

      return result.rows;
    });
    res.json(rows);
  } catch (err) {
    console.error('Error fetching reviews:', err);
    res.status(500).json({ error: 'Failed to fetch reviews' });
  }
});

// POST /api/products/:productId/reviews                 CUJ: product-review
router.post('/', async (req, res) => {
  try {
    const row = await withJourney('product-review', async () => {
      const { productId } = req.params;
      const { rating, reviewer_name, comment } = req.body;

      if (!rating || rating < 1 || rating > 5) {
        const err = new Error('Rating must be between 1 and 5');
        err.status = 400;
        throw err;
      }
      if (!reviewer_name || !reviewer_name.trim()) {
        const err = new Error('Reviewer name is required');
        err.status = 400;
        throw err;
      }

      const result = await db.query(
        'INSERT INTO reviews (product_id, rating, reviewer_name, comment) VALUES ($1, $2, $3, $4) RETURNING id, product_id, rating, reviewer_name, comment, created_at',
        [productId, rating, reviewer_name.trim(), comment || '']
      );

      const span = trace.getActiveSpan();
      if (span) {
        span.setAttribute('review.product_id', parseInt(productId));
        span.setAttribute('review.rating', rating);
      }

      return result.rows[0];
    });
    res.status(201).json(row);
  } catch (err) {
    console.error('Error creating review:', err);
    const status = err.status || 500;
    res.status(status).json({ error: err.message || 'Failed to create review' });
  }
});

module.exports = router;
