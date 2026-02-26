import React, { useEffect, useState, useCallback } from 'react';

async function fetchProducts() {
  const res = await fetch('/api/products');
  if (!res.ok) {
    throw new Error(`Server returned ${res.status} ${res.statusText}`);
  }
  const contentType = res.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) {
    // Ingress or nginx returned HTML instead of JSON — usually a startup race.
    // Throw a message the user can act on rather than a cryptic parse error.
    throw new Error('API not ready yet — please retry in a moment.');
  }
  return res.json();
}

export default function ProductGrid({ onAddToCart }) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    fetchProducts()
      .then(data => { setProducts(data); setLoading(false); })
      .catch(err => { setError(err.message); setLoading(false); });
  }, []);

  useEffect(() => { load(); }, [load]);

  if (loading) return <div className="loading">Loading products…</div>;

  if (error) {
    return (
      <div className="page-error">
        <p>⚠️ {error}</p>
        <button className="add-btn" style={{ marginTop: '1rem' }} onClick={load}>
          Retry
        </button>
      </div>
    );
  }

  return (
    <div>
      <h1 className="section-title">All Products</h1>
      <div className="product-grid">
        {products.map(product => (
          <ProductCard key={product.id} product={product} onAddToCart={onAddToCart} />
        ))}
      </div>
    </div>
  );
}

function ProductCard({ product, onAddToCart }) {
  const [added, setAdded] = useState(false);

  const handleAdd = () => {
    onAddToCart(product);
    setAdded(true);
    setTimeout(() => setAdded(false), 1200);
  };

  return (
    <div className="product-card">
      <div className="product-emoji-wrap">{product.emoji}</div>
      <div className="product-body">
        <span className="product-category">{product.category}</span>
        <h3 className="product-name">{product.name}</h3>
        <p className="product-desc">{product.description}</p>
        <div className="product-footer">
          <span className="product-price">${parseFloat(product.price).toFixed(2)}</span>
          <button
            className="add-btn"
            onClick={handleAdd}
            disabled={product.stock === 0}
          >
            {product.stock === 0 ? 'Out of Stock' : added ? '✓ Added' : 'Add to Cart'}
          </button>
        </div>
      </div>
    </div>
  );
}
