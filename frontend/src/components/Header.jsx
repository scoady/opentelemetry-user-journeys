import React from 'react';

export default function Header({ cartCount, onCartOpen, onLogoClick, onOrderHistory, onAdmin }) {
  return (
    <header className="header">
      <div className="header-inner">
        <span className="logo" onClick={onLogoClick}>
          🛒 scoady.local
        </span>
        <div className="header-actions">
          <button className="nav-btn" onClick={onAdmin}>Admin</button>
          <button className="nav-btn" onClick={onOrderHistory}>My Orders</button>
          <button className="cart-btn" onClick={onCartOpen}>
            🛍️ Cart
            {cartCount > 0 && (
              <span className="cart-badge">{cartCount}</span>
            )}
          </button>
        </div>
      </div>
    </header>
  );
}
