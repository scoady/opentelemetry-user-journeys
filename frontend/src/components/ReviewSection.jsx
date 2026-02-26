import React, { useEffect, useState } from 'react';

function Stars({ rating, interactive, onSelect }) {
  return (
    <span className="stars">
      {[1, 2, 3, 4, 5].map(n => (
        <span
          key={n}
          className={`star ${n <= rating ? 'star-filled' : 'star-empty'}${interactive ? ' star-interactive' : ''}`}
          onClick={interactive ? () => onSelect(n) : undefined}
        >
          {n <= rating ? '\u2605' : '\u2606'}
        </span>
      ))}
    </span>
  );
}

export default function ReviewSection({ productId, productName, onClose }) {
  const [reviews, setReviews] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState('');
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch(`/api/products/${productId}/reviews`)
      .then(r => r.json())
      .then(data => { setReviews(data); setLoading(false); })
      .catch(() => setLoading(false));
  }, [productId]);

  const avgRating = reviews.length > 0
    ? (reviews.reduce((s, r) => s + r.rating, 0) / reviews.length).toFixed(1)
    : null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!rating || !name.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch(`/api/products/${productId}/reviews`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rating, reviewer_name: name.trim(), comment }),
      });
      if (!res.ok) throw new Error('Failed to submit review');
      const newReview = await res.json();
      setReviews(prev => [newReview, ...prev]);
      setShowForm(false);
      setName('');
      setRating(0);
      setComment('');
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="review-overlay" onClick={onClose}>
      <div className="review-panel" onClick={e => e.stopPropagation()}>
        <div className="review-header">
          <div>
            <h2>Reviews</h2>
            <p className="review-product-name">{productName}</p>
            {avgRating && (
              <p className="review-avg">
                <Stars rating={Math.round(parseFloat(avgRating))} /> {avgRating} ({reviews.length} review{reviews.length !== 1 ? 's' : ''})
              </p>
            )}
          </div>
          <button className="close-btn" onClick={onClose}>&times;</button>
        </div>

        <div className="review-actions">
          <button className="add-btn" onClick={() => setShowForm(!showForm)}>
            {showForm ? 'Cancel' : 'Write a Review'}
          </button>
        </div>

        {showForm && (
          <form className="review-form" onSubmit={handleSubmit}>
            <div className="form-group">
              <label>Your Name</label>
              <input
                type="text"
                value={name}
                onChange={e => setName(e.target.value)}
                placeholder="Enter your name"
                required
              />
            </div>
            <div className="form-group">
              <label>Rating</label>
              <Stars rating={rating} interactive onSelect={setRating} />
            </div>
            <div className="form-group">
              <label>Comment (optional)</label>
              <textarea
                className="review-textarea"
                value={comment}
                onChange={e => setComment(e.target.value)}
                placeholder="Share your experience..."
                rows={3}
              />
            </div>
            {error && <p className="error-msg">{error}</p>}
            <button
              type="submit"
              className="place-order-btn"
              disabled={submitting || !rating || !name.trim()}
            >
              {submitting ? 'Submitting...' : 'Submit Review'}
            </button>
          </form>
        )}

        <div className="review-list">
          {loading ? (
            <div className="loading">Loading reviews...</div>
          ) : reviews.length === 0 ? (
            <div className="loading">No reviews yet. Be the first!</div>
          ) : (
            reviews.map(r => (
              <div key={r.id} className="review-card">
                <div className="review-card-header">
                  <strong>{r.reviewer_name}</strong>
                  <Stars rating={r.rating} />
                </div>
                {r.comment && <p className="review-comment">{r.comment}</p>}
                <p className="review-date">{new Date(r.created_at).toLocaleDateString()}</p>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
