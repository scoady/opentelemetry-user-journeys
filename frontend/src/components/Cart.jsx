import React from 'react';

export default function Cart({ cart, onClose, onUpdateQty, onCheckout }) {
  const total = cart.reduce((sum, item) => sum + item.price * item.qty, 0);
  const itemCount = cart.reduce((sum, item) => sum + item.qty, 0);

  return (
    <div className="cart-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="cart-panel">
        <div className="cart-header">
          <h2>Your Cart {itemCount > 0 && `(${itemCount})`}</h2>
          <button className="close-btn" onClick={onClose}>×</button>
        </div>

        <div className="cart-items">
          {cart.length === 0 ? (
            <div className="cart-empty">
              <div style={{ fontSize: '3rem' }}>🛒</div>
              <p>Your cart is empty.</p>
            </div>
          ) : (
            cart.map(item => (
              <div key={item.id} className="cart-item">
                <span className="cart-item-emoji">{item.emoji}</span>
                <div className="cart-item-info">
                  <div className="cart-item-name">{item.name}</div>
                  <div className="cart-item-price">
                    ${(item.price * item.qty).toFixed(2)}
                    {item.qty > 1 && ` (${item.qty} × $${parseFloat(item.price).toFixed(2)})`}
                  </div>
                </div>
                <div className="qty-controls">
                  <button className="qty-btn" onClick={() => onUpdateQty(item.id, item.qty - 1)}>−</button>
                  <span className="qty-num">{item.qty}</span>
                  <button className="qty-btn" onClick={() => onUpdateQty(item.id, item.qty + 1)}>+</button>
                </div>
              </div>
            ))
          )}
        </div>

        {cart.length > 0 && (
          <div className="cart-footer">
            <div className="cart-total">
              <span>Total</span>
              <span>${total.toFixed(2)}</span>
            </div>
            <button className="checkout-btn" onClick={onCheckout}>
              Checkout →
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
