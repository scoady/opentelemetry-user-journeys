import React, { useState, useEffect, useRef } from 'react';

const CATEGORIES = ['Audio', 'Wearables', 'Accessories', 'Peripherals', 'Smart Home', 'Gaming'];
const EMOJIS_BY_CATEGORY = {
  Audio: ['🎧', '🔊', '🎵', '🎤'],
  Wearables: ['⌚', '💍', '🕶️'],
  Accessories: ['🔌', '💻', '🖥️', '🔋'],
  Peripherals: ['⌨️', '🖱️', '📷', '🖨️'],
  'Smart Home': ['💡', '🏠', '📡', '🔒'],
  Gaming: ['🎮', '🕹️', '🎯'],
};
const ADJECTIVES = ['Pro', 'Ultra', 'Mini', 'Max', 'Lite', 'Elite', 'Smart', 'Wireless', 'Portable', 'Premium'];
const NOUNS_BY_CATEGORY = {
  Audio: ['Speaker', 'Headphones', 'Earbuds', 'Soundbar', 'Microphone'],
  Wearables: ['Watch', 'Fitness Band', 'Ring', 'Glasses'],
  Accessories: ['Hub', 'Charger', 'Cable', 'Stand', 'Dock'],
  Peripherals: ['Keyboard', 'Mouse', 'Webcam', 'Monitor', 'Printer'],
  'Smart Home': ['Bulb', 'Thermostat', 'Camera', 'Lock', 'Sensor'],
  Gaming: ['Controller', 'Headset', 'Pad', 'Chair'],
};

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

function generateProducts(count) {
  const products = [];
  for (let i = 0; i < count; i++) {
    const category = pick(CATEGORIES);
    const adj = pick(ADJECTIVES);
    const noun = pick(NOUNS_BY_CATEGORY[category]);
    const emoji = pick(EMOJIS_BY_CATEGORY[category]);
    const price = parseFloat((Math.random() * 200 + 10).toFixed(2));
    products.push({
      name: `${adj} ${noun}`,
      description: `High-quality ${adj.toLowerCase()} ${noun.toLowerCase()} for everyday use.`,
      price,
      emoji,
      category,
      stock: Math.floor(Math.random() * 200) + 10,
    });
  }
  return products;
}

export default function Admin({ onBack }) {
  const [count, setCount] = useState(10);
  const [products, setProducts] = useState(null);
  const [jsonText, setJsonText] = useState('');
  const [job, setJob] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState(null);
  const pollRef = useRef(null);
  const startTimeRef = useRef(null);
  const [elapsed, setElapsed] = useState(null);

  useEffect(() => () => {
    if (pollRef.current) clearInterval(pollRef.current);
  }, []);

  const handleGenerate = () => {
    const generated = generateProducts(Math.max(1, Math.min(count, 500)));
    setProducts(generated);
    setJsonText(JSON.stringify(generated, null, 2));
    setJob(null);
    setError(null);
    setElapsed(null);
  };

  const handleUpload = async () => {
    let parsed;
    try {
      parsed = JSON.parse(jsonText);
      if (!Array.isArray(parsed) || parsed.length === 0) throw new Error();
    } catch {
      setError('Invalid JSON — must be a non-empty array of products');
      return;
    }

    setUploading(true);
    setError(null);
    startTimeRef.current = Date.now();

    try {
      const res = await fetch('/api/admin/upload-products', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ products: parsed }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error || `Server returned ${res.status}`);
      }
      const data = await res.json();
      setJob(data);

      pollRef.current = setInterval(async () => {
        try {
          const pollRes = await fetch(`/api/admin/jobs/${data.job_id}`);
          if (pollRes.ok) {
            const jobData = await pollRes.json();
            setJob(jobData);
            setElapsed(((Date.now() - startTimeRef.current) / 1000).toFixed(1));
            if (jobData.status === 'completed' || jobData.status === 'failed') {
              clearInterval(pollRef.current);
              pollRef.current = null;
            }
          }
        } catch { /* ignore polling errors */ }
      }, 1000);
    } catch (err) {
      setError(err.message);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="admin-wrap">
      <button className="back-link" onClick={onBack}>&larr; Back to Products</button>
      <h1 className="section-title">Admin: Bulk Product Upload</h1>

      <div className="admin-card">
        <div className="admin-section">
          <h2 className="admin-section-title">1. Generate Products</h2>
          <div className="admin-controls">
            <label>Number of products:</label>
            <input
              type="number"
              min="1"
              max="500"
              value={count}
              onChange={e => setCount(parseInt(e.target.value) || 1)}
            />
            <button className="add-btn" onClick={handleGenerate}>Generate</button>
          </div>
        </div>

        {products && (
          <div className="admin-section">
            <h2 className="admin-section-title">2. Review &amp; Edit JSON</h2>
            <textarea
              className="admin-json"
              value={jsonText}
              onChange={e => setJsonText(e.target.value)}
              rows={12}
            />
            <p className="admin-hint">{products.length} products generated. Edit the JSON if needed.</p>
          </div>
        )}

        {products && !job && (
          <div className="admin-section">
            <h2 className="admin-section-title">3. Upload to Database</h2>
            <button
              className="add-btn admin-upload-btn"
              onClick={handleUpload}
              disabled={uploading}
            >
              {uploading ? 'Uploading...' : 'Insert into Product DB'}
            </button>
          </div>
        )}

        {error && <p className="error-msg">{error}</p>}

        {job && (
          <div className="job-status-panel">
            <h2 className="admin-section-title">Job Status</h2>
            <div className="job-status-row">
              <span>Status:</span>
              <span className={`job-status-badge job-status-${job.status}`}>{job.status}</span>
            </div>
            <div className="job-status-row">
              <span>Products:</span>
              <span>{job.processed_count || 0} / {job.total_products}</span>
            </div>
            {elapsed && (
              <div className="job-status-row">
                <span>Elapsed:</span>
                <span>{elapsed}s</span>
              </div>
            )}
            {job.trace_id && (
              <div className="job-status-row">
                <span>Trace ID:</span>
                <code className="trace-link">{job.trace_id}</code>
              </div>
            )}
            {job.error_message && (
              <div className="job-status-row">
                <span>Error:</span>
                <span className="error-text">{job.error_message}</span>
              </div>
            )}
            {job.status === 'completed' && (
              <p className="job-success">All {job.processed_count} products inserted successfully.</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
