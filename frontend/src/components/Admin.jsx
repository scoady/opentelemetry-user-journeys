import React, { useState, useEffect, useRef, useCallback } from 'react';

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

// ── Chaos row sub-component ──────────────────────────────────────────────────
function ChaosRow({ cuj, fault, onSet, onClear }) {
  const isActive = !!fault;
  const [delayMs, setDelayMs] = useState(fault?.delayMs || 3000);
  const [errorRate, setErrorRate] = useState(fault?.errorRate || 0);

  return (
    <div className={`chaos-row ${isActive ? 'active' : ''}`}>
      <div className="chaos-cuj-name">
        <span className={`chaos-dot ${isActive ? 'on' : 'off'}`} />
        {cuj}
      </div>
      <div className="chaos-controls">
        <label>Delay:</label>
        <input
          type="number"
          min="0"
          step="500"
          value={delayMs}
          onChange={e => setDelayMs(parseInt(e.target.value) || 0)}
          className="chaos-input"
        />
        <span className="chaos-unit">ms</span>
        <label>Error:</label>
        <input
          type="number"
          min="0"
          max="1"
          step="0.1"
          value={errorRate}
          onChange={e => setErrorRate(parseFloat(e.target.value) || 0)}
          className="chaos-input chaos-input-sm"
        />
        {isActive ? (
          <button className="chaos-btn chaos-btn-clear" onClick={() => onClear(cuj)}>
            Clear
          </button>
        ) : (
          <button
            className="chaos-btn chaos-btn-inject"
            onClick={() => onSet(cuj, delayMs, errorRate)}
          >
            Inject
          </button>
        )}
      </div>
    </div>
  );
}

// ── Main Admin component ─────────────────────────────────────────────────────
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

  // Chaos state
  const [chaosConfig, setChaosConfig] = useState({ faults: {}, validCujs: [] });
  const [inventoryDelay, setInventoryDelay] = useState(500);
  const [chaosLoading, setChaosLoading] = useState(true);

  useEffect(() => () => {
    if (pollRef.current) clearInterval(pollRef.current);
  }, []);

  // ── Chaos fetchers ──
  const fetchChaos = useCallback(async () => {
    try {
      const [chaosRes, delayRes] = await Promise.all([
        fetch('/api/admin/chaos'),
        fetch('/api/admin/chaos/inventory-delay'),
      ]);
      if (chaosRes.ok) setChaosConfig(await chaosRes.json());
      if (delayRes.ok) {
        const d = await delayRes.json();
        setInventoryDelay(d.delayMs);
      }
    } catch { /* ignore */ }
    setChaosLoading(false);
  }, []);

  useEffect(() => { fetchChaos(); }, [fetchChaos]);

  const handleSetFault = async (cuj, delayMs, errorRate) => {
    await fetch(`/api/admin/chaos/${cuj}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ delayMs, errorRate }),
    });
    fetchChaos();
  };

  const handleClearFault = async (cuj) => {
    await fetch(`/api/admin/chaos/${cuj}`, { method: 'DELETE' });
    fetchChaos();
  };

  const handleClearAll = async () => {
    await Promise.all([
      fetch('/api/admin/chaos', { method: 'DELETE' }),
      fetch('/api/admin/chaos/inventory-delay', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ delayMs: 500 }),
      }),
    ]);
    fetchChaos();
  };

  const handleInventoryDelay = async (ms) => {
    await fetch('/api/admin/chaos/inventory-delay', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ delayMs: ms }),
    });
    fetchChaos();
  };

  // ── Upload handlers ──
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
      <h1 className="section-title">Admin</h1>

      {/* ── Bulk Product Upload ── */}
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

      {/* ── Chaos Engineering ── */}
      <div className="chaos-card">
        <div className="chaos-header">
          <h2 className="admin-section-title">Chaos Engineering</h2>
          <button className="chaos-reset-btn" onClick={handleClearAll}>
            Reset All
          </button>
        </div>
        <p className="admin-hint">
          Inject latency or errors into CUJs at runtime. Faults are in-memory and clear on pod restart.
        </p>

        {/* Scenario A: Downstream service delay */}
        <div className="chaos-scenario">
          <h3 className="chaos-scenario-title">Downstream Service Delay</h3>
          <p className="admin-hint">
            Controls the inventory-svc artificial delay. Affects the checkout CUJ — the HTTP span
            to inventory-svc will show the full delay in trace waterfalls.
          </p>
          <div className="chaos-delay-row">
            <label>inventory-svc delay:</label>
            <span className="chaos-current">{inventoryDelay}ms</span>
            <div className="chaos-presets">
              {[500, 2000, 5000, 10000].map(ms => (
                <button
                  key={ms}
                  className={`chaos-preset ${inventoryDelay === ms ? 'active' : ''}`}
                  onClick={() => handleInventoryDelay(ms)}
                >
                  {ms >= 1000 ? `${ms / 1000}s` : `${ms}ms`}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Scenario B: Per-CUJ fault injection */}
        <div className="chaos-scenario">
          <h3 className="chaos-scenario-title">CUJ Fault Injection</h3>
          <p className="admin-hint">
            Inject delay or errors directly into CUJ spans. Shows as chaos.delay / chaos.error
            child spans in traces.
          </p>
          {chaosLoading ? (
            <p className="loading">Loading...</p>
          ) : (
            <div className="chaos-cuj-list">
              {chaosConfig.validCujs.map(cuj => (
                <ChaosRow
                  key={cuj}
                  cuj={cuj}
                  fault={chaosConfig.faults[cuj] || null}
                  onSet={handleSetFault}
                  onClear={handleClearFault}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
