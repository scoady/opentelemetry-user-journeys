#!/usr/bin/env bash
# build-and-load.sh — Build Docker images and load them into the kind cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo ">>> Building Docker images…"

echo "  [1/2] Building API image (webstore/api:latest)…"
docker build -t webstore/api:latest "${ROOT_DIR}/api"

echo "  [2/2] Building Frontend image (webstore/frontend:latest)…"
docker build -t webstore/frontend:latest "${ROOT_DIR}/frontend"

echo ""
echo ">>> Loading images into kind cluster 'techmart'…"

echo "  Loading webstore/api:latest…"
kind load docker-image webstore/api:latest --name techmart

echo "  Loading webstore/frontend:latest…"
kind load docker-image webstore/frontend:latest --name techmart

echo ""
echo "✓ Images loaded!"
echo "  Run ./infrastructure/scripts/deploy.sh to apply Kubernetes manifests."
