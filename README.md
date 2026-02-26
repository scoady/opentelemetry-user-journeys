# TechMart - 3-Tier Web Store

A functional fake tech gadget store demonstrating a 3-tier web application deployed on Kubernetes via kind.

## Architecture

- **Tier 1 (Frontend):** React + Vite — product catalog, cart, checkout flow
- **Tier 2 (API):** Node.js + Express — REST API for products and orders
- **Tier 3 (Database):** PostgreSQL — products, orders, order_items

## Directory Structure

```
.
├── frontend/         # Tier 1 — React web store
├── api/              # Tier 2 — Express REST API
├── database/         # Tier 3 — PostgreSQL init scripts
└── infrastructure/
    ├── kind/         # Kind cluster configuration
    ├── k8s/          # Kubernetes manifests
    │   ├── frontend/
    │   ├── api/
    │   └── database/
    └── scripts/      # Setup and deploy scripts
```

## Quick Start

See `infrastructure/scripts/` for setup instructions.
