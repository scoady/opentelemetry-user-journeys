import React from 'react';

export default function Header({ cartCount, onCartOpen, onLogoClick }) {
  return (
    <header className="header">
      <div className="header-inner">
        <span className="logo" onClick={onLogoClick}>
          🛒 TechMart
        </span>
        <button className="cart-btn" onClick={onCartOpen}>
          🛍️ Cart
          {cartCount > 0 && (
            <span className="cart-badge">{cartCount}</span>
          )}
        </button>
      </div>
    </header>
  );
}
