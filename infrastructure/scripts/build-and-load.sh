#!/usr/bin/env bash
# build-and-load.sh — Build Docker images, load them into kind, and restart pods
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

# kind uses imagePullPolicy: Never, so pods keep the old image layer until
# they are replaced. Force a rollout restart to pick up the freshly loaded images.
if kubectl get namespace webstore &>/dev/null; then
  echo ""
  echo ">>> Restarting deployments to pick up new images…"
  kubectl rollout restart deployment/api deployment/frontend -n webstore
  kubectl rollout status deployment/api      -n webstore --timeout=120s
  kubectl rollout status deployment/frontend -n webstore --timeout=120s
  echo "✓ Deployments updated."
else
  echo ""
  echo "✓ Images loaded."
  echo "  (Namespace 'webstore' not found — run deploy.sh to apply manifests.)"
fi
