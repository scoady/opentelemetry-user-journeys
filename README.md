# TechMart — 3-Tier Web Store on Kubernetes

A functional fake tech gadget store demonstrating a 3-tier web application deployed on a local Kubernetes cluster via [kind](https://kind.sigs.k8s.io/).

## Architecture

```
Browser
  │
  ▼
[Ingress - NGINX]
  │         │
  │ /api    │ /
  ▼         ▼
[API]   [Frontend]
  │     (React SPA)
  ▼
[PostgreSQL]
```

| Tier | Technology | Description |
|------|-----------|-------------|
| **Tier 1 — Frontend** | React + Vite + nginx | Product catalog, sliding cart, checkout form, order confirmation |
| **Tier 2 — API** | Node.js + Express | REST API: products listing, transactional order creation |
| **Tier 3 — Database** | PostgreSQL 16 | Products catalog + orders with stock management |

## Features

- Browse 8 gadget products with categories
- Slide-out shopping cart with quantity controls
- Full checkout form (customer info, shipping, fake payment)
- Transactional order creation (validates stock, decrements on purchase)
- Order confirmation with order ID

## Directory Structure

```
.
├── frontend/                   # Tier 1 — React web store
│   ├── src/
│   │   ├── App.jsx             # Root component, view routing
│   │   ├── App.css             # All styles
│   │   └── components/
│   │       ├── Header.jsx
│   │       ├── ProductGrid.jsx
│   │       ├── Cart.jsx
│   │       ├── CheckoutForm.jsx
│   │       └── OrderConfirmation.jsx
│   ├── Dockerfile              # Multi-stage: Vite build → nginx:alpine
│   ├── nginx.conf              # SPA routing config
│   └── package.json
│
├── api/                        # Tier 2 — Express REST API
│   ├── src/
│   │   ├── index.js            # Express app
│   │   ├── db.js               # pg Pool
│   │   └── routes/
│   │       ├── products.js     # GET /api/products[/:id]
│   │       └── orders.js       # POST /api/orders, GET /api/orders/:id
│   ├── Dockerfile
│   └── package.json
│
├── database/                   # Tier 3 — PostgreSQL
│   └── init.sql                # Schema + seed data (8 products)
│
└── infrastructure/
    ├── kind/
    │   └── cluster.yaml        # kind cluster: 1 control-plane + 2 workers
    ├── k8s/
    │   ├── namespace.yaml
    │   ├── database/           # secret, pvc, configmap, deployment, service
    │   ├── api/                # configmap, deployment, service
    │   └── frontend/           # deployment, service, ingress
    └── scripts/
        ├── setup-cluster.sh    # Create kind cluster + install NGINX ingress
        ├── build-and-load.sh   # Build Docker images + load into kind
        ├── deploy.sh           # Apply all k8s manifests in order
        └── teardown.sh         # Delete the cluster
```

## Quick Start

### Prerequisites

- Docker Desktop (running)
- Homebrew (for auto-installing `kind` and `kubectl` if missing)

### 1. Create the cluster

```bash
./infrastructure/scripts/setup-cluster.sh
```

This will:
- Install `kind` and `kubectl` if not present (via Homebrew)
- Create a 3-node kind cluster named `techmart`
- Install the NGINX Ingress Controller

### 2. Build and load images

```bash
./infrastructure/scripts/build-and-load.sh
```

This builds both Docker images locally and loads them into the kind cluster (no registry needed).

### 3. Deploy

```bash
./infrastructure/scripts/deploy.sh
```

Applies all manifests in dependency order and waits for each tier to be healthy.

### 4. Open the store

Visit **http://localhost** in your browser.

### Teardown

```bash
./infrastructure/scripts/teardown.sh
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/health` | Health check (DB connectivity) |
| `GET` | `/api/products` | List all products |
| `GET` | `/api/products/:id` | Single product |
| `POST` | `/api/orders` | Create order (transactional) |
| `GET` | `/api/orders/:id` | Get order details |

### Create Order — Request Body

```json
{
  "customer_name": "Jane Smith",
  "customer_email": "jane@example.com",
  "shipping_address": "123 Main St, Springfield, IL 62701",
  "items": [
    { "product_id": 1, "quantity": 2 },
    { "product_id": 5, "quantity": 1 }
  ]
}
```

## Local Development (without Kubernetes)

```bash
# Start PostgreSQL
docker run -e POSTGRES_DB=techmart -e POSTGRES_USER=techmart \
  -e POSTGRES_PASSWORD=techmart-secret-pw \
  -v $(pwd)/database/init.sql:/docker-entrypoint-initdb.d/init.sql \
  -p 5432:5432 postgres:16-alpine

# Start API
cd api && npm install
DATABASE_URL=postgresql://techmart:techmart-secret-pw@localhost:5432/techmart npm start

# Start Frontend (in another terminal)
cd frontend && npm install && npm run dev
# Open http://localhost:3000
```
