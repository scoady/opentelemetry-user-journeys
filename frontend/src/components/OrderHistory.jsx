import React, { useState } from 'react';

export default function OrderHistory({ onBack }) {
  const [email, setEmail] = useState('');
  const [orders, setOrders] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSearch = async (e) => {
    e.preventDefault();
    if (!email.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/orders?email=${encodeURIComponent(email.trim())}`);
      if (!res.ok) throw new Error(`Server returned ${res.status}`);
      const data = await res.json();
      setOrders(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="order-history-wrap">
      <button className="back-link" onClick={onBack}>&larr; Back to Products</button>
      <h1 className="section-title">Order History</h1>

      <form className="order-history-form" onSubmit={handleSearch}>
        <input
          type="email"
          className="search-input"
          placeholder="Enter your email address..."
          value={email}
          onChange={e => setEmail(e.target.value)}
          required
        />
        <button type="submit" className="add-btn" disabled={loading}>
          {loading ? 'Searching...' : 'Look Up Orders'}
        </button>
      </form>

      {error && <p className="error-msg">{error}</p>}

      {orders !== null && !loading && (
        orders.length === 0 ? (
          <div className="loading">No orders found for {email}.</div>
        ) : (
          <div className="order-history-list">
            <p className="order-history-count">{orders.length} order{orders.length !== 1 ? 's' : ''} found</p>
            {orders.map(order => (
              <div key={order.id} className="order-history-card">
                <div className="order-history-card-header">
                  <span className="order-id-tag">Order #{order.id}</span>
                  <span className={`order-status order-status-${order.status}`}>{order.status}</span>
                </div>
                <div className="order-history-details">
                  <p><strong>{order.customer_name}</strong></p>
                  <p>{order.item_count} item{order.item_count !== 1 ? 's' : ''} &middot; ${parseFloat(order.total).toFixed(2)}</p>
                  <p className="order-history-date">{new Date(order.created_at).toLocaleString()}</p>
                </div>
              </div>
            ))}
          </div>
        )
      )}
    </div>
  );
}
