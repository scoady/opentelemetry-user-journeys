import React, { useState } from 'react';
import Header from './components/Header';
import ProductGrid from './components/ProductGrid';
import Cart from './components/Cart';
import CheckoutForm from './components/CheckoutForm';
import OrderConfirmation from './components/OrderConfirmation';
import OrderHistory from './components/OrderHistory';

// Views: 'catalog' | 'checkout' | 'confirmation' | 'orders'
export default function App() {
  const [view, setView] = useState('catalog');
  const [cart, setCart] = useState([]);
  const [cartOpen, setCartOpen] = useState(false);
  const [completedOrder, setCompletedOrder] = useState(null);

  const cartCount = cart.reduce((sum, item) => sum + item.qty, 0);

  const addToCart = (product) => {
    setCart(prev => {
      const existing = prev.find(i => i.id === product.id);
      if (existing) {
        return prev.map(i => i.id === product.id ? { ...i, qty: i.qty + 1 } : i);
      }
      return [...prev, { ...product, qty: 1 }];
    });
  };

  const updateQty = (id, qty) => {
    if (qty <= 0) {
      setCart(prev => prev.filter(i => i.id !== id));
    } else {
      setCart(prev => prev.map(i => i.id === id ? { ...i, qty } : i));
    }
  };

  const handleCheckout = () => {
    setCartOpen(false);
    setView('checkout');
  };

  const handleOrderPlaced = (order) => {
    setCompletedOrder(order);
    setCart([]);
    setView('confirmation');
  };

  const handleContinueShopping = () => {
    setCompletedOrder(null);
    setView('catalog');
  };

  return (
    <>
      <Header
        cartCount={cartCount}
        onCartOpen={() => setCartOpen(true)}
        onLogoClick={handleContinueShopping}
        onOrderHistory={() => setView('orders')}
      />

      <main className="main">
        {view === 'catalog' && (
          <ProductGrid onAddToCart={addToCart} />
        )}
        {view === 'checkout' && (
          <CheckoutForm
            cart={cart}
            onBack={() => { setView('catalog'); setCartOpen(true); }}
            onOrderPlaced={handleOrderPlaced}
          />
        )}
        {view === 'confirmation' && completedOrder && (
          <OrderConfirmation
            order={completedOrder}
            onContinue={handleContinueShopping}
          />
        )}
        {view === 'orders' && (
          <OrderHistory onBack={handleContinueShopping} />
        )}
      </main>

      {cartOpen && (
        <Cart
          cart={cart}
          onClose={() => setCartOpen(false)}
          onUpdateQty={updateQty}
          onCheckout={handleCheckout}
        />
      )}
    </>
  );
}
