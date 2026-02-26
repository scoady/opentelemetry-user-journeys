#!/usr/bin/env bash
# setup-cluster.sh — Create the kind cluster and install the NGINX ingress controller
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KIND_CONFIG="${ROOT_DIR}/infrastructure/kind/cluster.yaml"

# ── 1. Ensure kind is installed ──────────────────────────────────────────────
if ! command -v kind &>/dev/null; then
  echo ">>> kind not found. Installing via Homebrew…"
  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Please install kind manually: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
  fi
  brew install kind
  echo ">>> kind installed: $(kind version)"
fi

# ── 2. Ensure kubectl is installed ───────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
  echo ">>> kubectl not found. Installing via Homebrew…"
  brew install kubectl
fi

# ── 3. Create (or reuse) the cluster ─────────────────────────────────────────
if kind get clusters 2>/dev/null | grep -q "^techmart$"; then
  echo ">>> Cluster 'techmart' already exists, skipping creation."
else
  echo ">>> Creating kind cluster 'techmart'…"
  kind create cluster --config "${KIND_CONFIG}"
fi

echo ">>> Setting kubectl context to kind-techmart…"
kubectl cluster-info --context kind-techmart

# ── 4. Install NGINX Ingress Controller ───────────────────────────────────────
echo ">>> Installing NGINX Ingress Controller…"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/kind/deploy.yaml

echo ">>> Waiting for ingress-nginx controller to be ready…"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo ""
echo "✓ Cluster 'techmart' is ready!"
echo "  Run ./infrastructure/scripts/build-and-load.sh to build and load images."
