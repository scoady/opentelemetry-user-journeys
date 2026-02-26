import React, { useEffect, useState, useCallback, useRef } from 'react';
import ReviewSection from './ReviewSection';

const CATEGORIES = ['All', 'Audio', 'Wearables', 'Accessories', 'Peripherals'];

async function fetchProducts() {
  const res = await fetch('/api/products');
  if (!res.ok) throw new Error(`Server returned ${res.status} ${res.statusText}`);
  const ct = res.headers.get('content-type') || '';
  if (!ct.includes('application/json')) throw new Error('API not ready yet — please retry in a moment.');
  return res.json();
}

async function searchProducts(q, category) {
  const params = new URLSearchParams();
  if (q) params.set('q', q);
  if (category && category !== 'All') params.set('category', category);
  const res = await fetch(`/api/products/search?${params}`);
  if (!res.ok) throw new Error(`Search failed: ${res.status}`);
  return res.json();
}

export default function ProductGrid({ onAddToCart }) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [category, setCategory] = useState('All');
  const [reviewProduct, setReviewProduct] = useState(null);
  const debounceRef = useRef(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    fetchProducts()
      .then(data => { setProducts(data); setLoading(false); })
      .catch(err => { setError(err.message); setLoading(false); });
  }, []);

  useEffect(() => { load(); }, [load]);

  // Debounced search
  useEffect(() => {
    if (!searchTerm && category === 'All') return;

    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setLoading(true);
      searchProducts(searchTerm, category)
        .then(data => { setProducts(data); setLoading(false); })
        .catch(err => { setError(err.message); setLoading(false); });
    }, 300);

    return () => clearTimeout(debounceRef.current);
  }, [searchTerm, category]);

  const handleClear = () => {
    setSearchTerm('');
    setCategory('All');
    load();
  };

  const isSearching = searchTerm || category !== 'All';

  if (error) {
    return (
      <div className="page-error">
        <p>⚠️ {error}</p>
        <button className="add-btn" style={{ marginTop: '1rem' }} onClick={load}>Retry</button>
      </div>
    );
  }

  return (
    <div>
      <h1 className="section-title">
        {isSearching ? `Search Results (${products.length})` : 'All Products'}
      </h1>

      <div className="search-bar">
        <input
          type="text"
          className="search-input"
          placeholder="Search products..."
          value={searchTerm}
          onChange={e => setSearchTerm(e.target.value)}
        />
        <select
          className="category-select"
          value={category}
          onChange={e => setCategory(e.target.value)}
        >
          {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        {isSearching && (
          <button className="add-btn" onClick={handleClear}>Clear</button>
        )}
      </div>

      {loading ? (
        <div className="loading">Loading products...</div>
      ) : products.length === 0 ? (
        <div className="loading">No products found.</div>
      ) : (
        <div className="product-grid">
          {products.map(product => (
            <ProductCard key={product.id} product={product} onAddToCart={onAddToCart} onReview={setReviewProduct} />
          ))}
        </div>
      )}

      {reviewProduct && (
        <ReviewSection
          productId={reviewProduct.id}
          productName={reviewProduct.name}
          onClose={() => setReviewProduct(null)}
        />
      )}
    </div>
  );
}

function ProductCard({ product, onAddToCart, onReview }) {
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
          <div className="product-actions">
            <button className="review-btn" onClick={() => onReview(product)}>Reviews</button>
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
    </div>
  );
}
