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

export default function () {
  const roll = Math.random();

  if (roll < 0.75) {
    // 75% — browse products
    const r = http.get(`${BASE_URL}/api/products`);
    check(r, { '200': (r) => r.status === 200 });
  } else {
    // 25% — place an order
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
    check(r, { '201': (r) => r.status === 201 });
  }
}
