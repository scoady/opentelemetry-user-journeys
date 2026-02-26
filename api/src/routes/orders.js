const express = require('express');
const router = express.Router();
const db = require('../db');
const { withJourney } = require('../tracing');

// POST /api/orders                                     CUJ: checkout
router.post('/', async (req, res) => {
  const { customer_name, customer_email, shipping_address, items } = req.body;

  if (!customer_name || !customer_email || !shipping_address || !items || items.length === 0) {
    return res.status(400).json({ error: 'Missing required order fields' });
  }

  const client = await db.connect();
  try {
    const order = await withJourney('checkout', async () => {
      await client.query('BEGIN');

      // Fetch prices and validate stock
      const productIds = items.map(i => i.product_id);
      const productResult = await client.query(
        'SELECT id, name, price, stock FROM products WHERE id = ANY($1)',
        [productIds]
      );

      const productMap = {};
      for (const p of productResult.rows) {
        productMap[p.id] = p;
      }

      for (const item of items) {
        const product = productMap[item.product_id];
        if (!product) throw new Error(`Product ${item.product_id} not found`);
        if (product.stock < item.quantity) throw new Error(`Insufficient stock for "${product.name}"`);
      }

      const total = items.reduce((sum, item) => {
        return sum + (parseFloat(productMap[item.product_id].price) * item.quantity);
      }, 0);

      const orderResult = await client.query(
        `INSERT INTO orders (customer_name, customer_email, shipping_address, total, status)
         VALUES ($1, $2, $3, $4, 'confirmed') RETURNING id, created_at`,
        [customer_name, customer_email, shipping_address, total.toFixed(2)]
      );
      const row = orderResult.rows[0];

      for (const item of items) {
        const product = productMap[item.product_id];
        await client.query(
          `INSERT INTO order_items (order_id, product_id, quantity, unit_price)
           VALUES ($1, $2, $3, $4)`,
          [row.id, item.product_id, item.quantity, product.price]
        );
        await client.query(
          'UPDATE products SET stock = stock - $1 WHERE id = $2',
          [item.quantity, item.product_id]
        );
      }

      await client.query('COMMIT');

      return {
        id: row.id,
        customer_name,
        customer_email,
        total: parseFloat(total.toFixed(2)),
        status: 'confirmed',
        created_at: row.created_at,
        item_count: items.reduce((sum, i) => sum + i.quantity, 0),
      };
    });

    res.status(201).json(order);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error creating order:', err);
    res.status(400).json({ error: err.message || 'Failed to create order' });
  } finally {
    client.release();
  }
});

// GET /api/orders/:id                                  CUJ: order-lookup
router.get('/:id', async (req, res) => {
  try {
    const result = await withJourney('order-lookup', async () => {
      const { id } = req.params;
      const orderResult = await db.query('SELECT * FROM orders WHERE id = $1', [id]);
      if (orderResult.rows.length === 0) {
        const err = new Error('Order not found');
        err.status = 404;
        throw err;
      }

      const itemsResult = await db.query(
        `SELECT oi.quantity, oi.unit_price, p.name, p.emoji
         FROM order_items oi
         JOIN products p ON oi.product_id = p.id
         WHERE oi.order_id = $1`,
        [id]
      );

      return { ...orderResult.rows[0], items: itemsResult.rows };
    });

    res.json(result);
  } catch (err) {
    console.error('Error fetching order:', err);
    const status = err.status || 500;
    res.status(status).json({ error: err.message || 'Failed to fetch order' });
  }
});

module.exports = router;
