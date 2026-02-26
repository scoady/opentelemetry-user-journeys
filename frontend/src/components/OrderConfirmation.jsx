import React from 'react';

export default function OrderConfirmation({ order, onContinue }) {
  return (
    <div className="confirmation-wrap">
      <div className="confirmation-icon">🎉</div>
      <h1 className="section-title" style={{ margin: 0 }}>Order Confirmed!</h1>
      <p style={{ color: 'var(--gray-600)', textAlign: 'center' }}>
        Thanks, <strong>{order.customer_name.split(' ')[0]}</strong>! Your gadgets are on their way.
      </p>

      <div className="confirmation-card">
        <h2>✓ Thank you for your purchase</h2>
        <div className="order-id-tag">
          Order #{String(order.id).padStart(5, '0')}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', fontSize: '0.9rem', color: 'var(--gray-600)' }}>
          <div><strong>Email:</strong> {order.customer_email}</div>
          <div><strong>Items:</strong> {order.item_count}</div>
          <div><strong>Total:</strong> ${parseFloat(order.total).toFixed(2)}</div>
          <div><strong>Status:</strong> <span style={{ color: 'var(--success)', fontWeight: 600 }}>Confirmed ✓</span></div>
          <div>
            <strong>Placed:</strong>{' '}
            {new Date(order.created_at).toLocaleString()}
          </div>
        </div>

        <p style={{ fontSize: '0.85rem', color: 'var(--gray-400)', marginTop: '0.25rem' }}>
          A confirmation would be sent to {order.customer_email} in a real store.
        </p>

        <button className="continue-btn" onClick={onContinue}>
          Continue Shopping
        </button>
      </div>
    </div>
  );
}
