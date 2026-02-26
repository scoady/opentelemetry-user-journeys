import http from 'k6/http';
import { check } from 'k6';

const BASE_URL    = __ENV.TARGET_URL || 'http://frontend.webstore.svc.cluster.local';
const RPS         = parseInt(__ENV.RPS || '5');
const PRODUCT_IDS = [1, 2, 3, 4, 5, 6, 7, 8];

export const options = {
  scenarios: {
    constant_rps: {
      executor:        'constant-arrival-rate',
      rate:            RPS,
      timeUnit:        '1s',
      duration:        '12h',
      preAllocatedVUs: RPS * 2,
    },
  },
};

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

const NAMES   = ['Alice', 'Bob', 'Carlos', 'Diana', 'Eve', 'Frank'];
const DOMAINS = ['example.com', 'test.io', 'loadtest.dev'];
const STREETS = ['1 Main St', '42 Oak Ave', '7 Elm Rd', '99 Pine Blvd'];

const SEARCH_TERMS = ['keyboard', 'audio', 'wireless', 'webcam', 'mouse', 'laptop', 'usb', 'speaker'];
const CATEGORIES   = ['Audio', 'Wearables', 'Accessories', 'Peripherals'];

// Per-VU order ID cache. k6 VUs are long-lived within a scenario so this
// accumulates real order IDs that can be looked up in the order-lookup CUJ.
// Capped at 50 to avoid unbounded growth.
let recentOrderIds = [];

export default function () {
  const roll = Math.random();

  if (roll < 0.55) {
    // 55% — browse products  (cuj.product-discovery)
    const r = http.get(`${BASE_URL}/api/products`);
    check(r, { '200': (r) => r.status === 200 });

  } else if (roll < 0.73) {
    // 18% — place an order  (cuj.checkout)
    const name = pick(NAMES);
    const r = http.post(
      `${BASE_URL}/api/orders`,
      JSON.stringify({
        customer_name:    name,
        customer_email:   `${name.toLowerCase()}@${pick(DOMAINS)}`,
        shipping_address: pick(STREETS),
        items: [{ product_id: pick(PRODUCT_IDS), quantity: 1 }],
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
    const ok = check(r, { '201': (r) => r.status === 201 });
    if (ok) {
      const body = JSON.parse(r.body);
      if (body.id) {
        recentOrderIds.push(body.id);
        if (recentOrderIds.length > 50) recentOrderIds.shift();
      }
    }

  } else if (roll < 0.85) {
    // 12% — look up a recent order  (cuj.order-lookup)
    if (recentOrderIds.length === 0) {
      const r = http.get(`${BASE_URL}/api/products`);
      check(r, { '200': (r) => r.status === 200 });
      return;
    }
    const id = pick(recentOrderIds);
    const r  = http.get(`${BASE_URL}/api/orders/${id}`);
    check(r, { '200': (r) => r.status === 200 });

  } else {
    // 15% — search products  (cuj.product-search)
    const term = pick(SEARCH_TERMS);
    const cat  = Math.random() < 0.3 ? `&category=${pick(CATEGORIES)}` : '';
    const r = http.get(`${BASE_URL}/api/products/search?q=${term}${cat}`);
    check(r, { '200': (r) => r.status === 200 });
  }
}
