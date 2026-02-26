const express = require('express');
const router = express.Router();
const db = require('../db');

// POST /api/orders
router.post('/', async (req, res) => {
  const { customer_name, customer_email, shipping_address, items } = req.body;

  if (!customer_name || !customer_email || !shipping_address || !items || items.length === 0) {
    return res.status(400).json({ error: 'Missing required order fields' });
  }

  const client = await db.connect();
  try {
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

    // Validate all products exist and have stock
    for (const item of items) {
      const product = productMap[item.product_id];
      if (!product) {
        throw new Error(`Product ${item.product_id} not found`);
      }
      if (product.stock < item.quantity) {
        throw new Error(`Insufficient stock for "${product.name}"`);
      }
    }

    // Calculate total
    const total = items.reduce((sum, item) => {
      return sum + (parseFloat(productMap[item.product_id].price) * item.quantity);
    }, 0);

    // Create order
    const orderResult = await client.query(
      `INSERT INTO orders (customer_name, customer_email, shipping_address, total, status)
       VALUES ($1, $2, $3, $4, 'confirmed') RETURNING id, created_at`,
      [customer_name, customer_email, shipping_address, total.toFixed(2)]
    );
    const order = orderResult.rows[0];

    // Create order items and decrement stock
    for (const item of items) {
      const product = productMap[item.product_id];
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price)
         VALUES ($1, $2, $3, $4)`,
        [order.id, item.product_id, item.quantity, product.price]
      );
      await client.query(
        'UPDATE products SET stock = stock - $1 WHERE id = $2',
        [item.quantity, item.product_id]
      );
    }

    await client.query('COMMIT');

    res.status(201).json({
      id: order.id,
      customer_name,
      customer_email,
      total: parseFloat(total.toFixed(2)),
      status: 'confirmed',
      created_at: order.created_at,
      item_count: items.reduce((sum, i) => sum + i.quantity, 0),
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Error creating order:', err);
    res.status(400).json({ error: err.message || 'Failed to create order' });
  } finally {
    client.release();
  }
});

// GET /api/orders/:id
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const orderResult = await db.query(
      'SELECT * FROM orders WHERE id = $1',
      [id]
    );
    if (orderResult.rows.length === 0) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const itemsResult = await db.query(
      `SELECT oi.quantity, oi.unit_price, p.name, p.emoji
       FROM order_items oi
       JOIN products p ON oi.product_id = p.id
       WHERE oi.order_id = $1`,
      [id]
    );

    res.json({
      ...orderResult.rows[0],
      items: itemsResult.rows,
    });
  } catch (err) {
    console.error('Error fetching order:', err);
    res.status(500).json({ error: 'Failed to fetch order' });
  }
});

module.exports = router;
