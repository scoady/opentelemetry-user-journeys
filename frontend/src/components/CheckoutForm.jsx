import React, { useState } from 'react';

function validate(form) {
  const errors = {};
  if (!form.name.trim()) errors.name = true;
  if (!form.email.trim() || !form.email.includes('@')) errors.email = true;
  if (!form.address.trim()) errors.address = true;
  if (!form.city.trim()) errors.city = true;
  if (!form.state.trim()) errors.state = true;
  if (!form.zip.trim()) errors.zip = true;
  if (form.card.replace(/\s/g, '').length < 12) errors.card = true;
  if (!form.expiry.match(/^\d{2}\/\d{2}$/)) errors.expiry = true;
  if (form.cvv.length < 3) errors.cvv = true;
  return errors;
}

export default function CheckoutForm({ cart, onBack, onOrderPlaced }) {
  const [form, setForm] = useState({
    name: '', email: '',
    address: '', city: '', state: '', zip: '',
    card: '', expiry: '', cvv: '',
  });
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [apiError, setApiError] = useState('');

  const total = cart.reduce((sum, item) => sum + item.price * item.qty, 0);

  const set = (field) => (e) => {
    let val = e.target.value;
    // Auto-format card number
    if (field === 'card') val = val.replace(/\D/g, '').replace(/(.{4})/g, '$1 ').trim().slice(0, 19);
    // Auto-format expiry
    if (field === 'expiry') {
      val = val.replace(/\D/g, '');
      if (val.length >= 2) val = val.slice(0, 2) + '/' + val.slice(2, 4);
    }
    setForm(f => ({ ...f, [field]: val }));
    setErrors(e => ({ ...e, [field]: false }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const errs = validate(form);
    if (Object.keys(errs).length > 0) {
      setErrors(errs);
      return;
    }

    setSubmitting(true);
    setApiError('');
    try {
      const res = await fetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          customer_name: form.name.trim(),
          customer_email: form.email.trim(),
          shipping_address: `${form.address.trim()}, ${form.city.trim()}, ${form.state.trim()} ${form.zip.trim()}`,
          items: cart.map(item => ({ product_id: item.id, quantity: item.qty })),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Order failed');
      onOrderPlaced(data);
    } catch (err) {
      setApiError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="checkout-wrap">
      <button className="back-link" onClick={onBack}>← Back to cart</button>
      <h1 className="section-title">Checkout</h1>

      <form className="checkout-card" onSubmit={handleSubmit} noValidate>

        {/* Customer info */}
        <div className="form-section">
          <h3>Customer Info</h3>
          <div className="form-row">
            <div className="form-group">
              <label>Full Name</label>
              <input
                type="text" placeholder="Jane Smith" value={form.name}
                onChange={set('name')} className={errors.name ? 'error' : ''}
              />
            </div>
          </div>
          <div className="form-row">
            <div className="form-group">
              <label>Email</label>
              <input
                type="email" placeholder="jane@example.com" value={form.email}
                onChange={set('email')} className={errors.email ? 'error' : ''}
              />
            </div>
          </div>
        </div>

        {/* Shipping */}
        <div className="form-section">
          <h3>Shipping Address</h3>
          <div className="form-row">
            <div className="form-group">
              <label>Street Address</label>
              <input
                type="text" placeholder="123 Main St" value={form.address}
                onChange={set('address')} className={errors.address ? 'error' : ''}
              />
            </div>
          </div>
          <div className="form-row">
            <div className="form-group" style={{ flex: 2 }}>
              <label>City</label>
              <input
                type="text" placeholder="Springfield" value={form.city}
                onChange={set('city')} className={errors.city ? 'error' : ''}
              />
            </div>
            <div className="form-group" style={{ flex: 1 }}>
              <label>State</label>
              <input
                type="text" placeholder="IL" value={form.state}
                onChange={set('state')} className={errors.state ? 'error' : ''}
              />
            </div>
            <div className="form-group" style={{ flex: 1 }}>
              <label>ZIP</label>
              <input
                type="text" placeholder="62701" value={form.zip}
                onChange={set('zip')} className={errors.zip ? 'error' : ''}
              />
            </div>
          </div>
        </div>

        {/* Payment */}
        <div className="form-section">
          <h3>Payment</h3>
          <p className="fake-card-note">This is a demo — no real payment is processed.</p>
          <div className="form-row" style={{ marginTop: '0.75rem' }}>
            <div className="form-group">
              <label>Card Number</label>
              <input
                type="text" placeholder="4242 4242 4242 4242" value={form.card}
                onChange={set('card')} className={errors.card ? 'error' : ''}
                maxLength={19}
              />
            </div>
          </div>
          <div className="form-row">
            <div className="form-group">
              <label>Expiry</label>
              <input
                type="text" placeholder="MM/YY" value={form.expiry}
                onChange={set('expiry')} className={errors.expiry ? 'error' : ''}
                maxLength={5}
              />
            </div>
            <div className="form-group">
              <label>CVV</label>
              <input
                type="text" placeholder="123" value={form.cvv}
                onChange={set('cvv')} className={errors.cvv ? 'error' : ''}
                maxLength={4}
              />
            </div>
          </div>
        </div>

        {/* Order summary */}
        <div className="order-summary-mini">
          <h3>Order Summary</h3>
          {cart.map(item => (
            <div key={item.id} className="order-line">
              <span>{item.emoji} {item.name} × {item.qty}</span>
              <span>${(item.price * item.qty).toFixed(2)}</span>
            </div>
          ))}
          <div className="order-line total">
            <span>Total</span>
            <span>${total.toFixed(2)}</span>
          </div>
        </div>

        {apiError && <div className="error-msg">⚠️ {apiError}</div>}

        <button type="submit" className="place-order-btn" disabled={submitting}>
          {submitting ? 'Placing order…' : `Place Order · $${total.toFixed(2)}`}
        </button>
      </form>
    </div>
  );
}
