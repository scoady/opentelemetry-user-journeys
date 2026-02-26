#!/usr/bin/env bash
# setup-cluster.sh — Create the kind cluster, install NGINX ingress, and add
#                    the Helm repos needed by setup-telemetry.sh.
#
# Run once per machine. Safe to re-run — all steps are idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KIND_CONFIG="${ROOT_DIR}/infrastructure/kind/cluster.yaml"

# ── 1. Ensure required tools are installed ────────────────────────────────────
for tool in kind kubectl helm; do
  if ! command -v "${tool}" &>/dev/null; then
    echo ">>> ${tool} not found. Installing via Homebrew…"
    if ! command -v brew &>/dev/null; then
      echo "ERROR: Homebrew not found. Install ${tool} manually and re-run."
      exit 1
    fi
    brew install "${tool}"
    echo ">>> ${tool} installed: $(${tool} version --short 2>/dev/null || ${tool} version)"
  fi
done

# ── 2. Add Helm repos (idempotent) ────────────────────────────────────────────
echo ">>> Adding Helm repositories…"
helm repo add jetstack        https://charts.jetstack.io                               --force-update
helm repo add open-telemetry  https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
helm repo update
echo "  Repos: jetstack, open-telemetry — up to date."

# ── 3. Create (or reuse) the cluster ──────────────────────────────────────────
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
echo ""
echo "  Next steps:"
echo "    1. Build and load images:"
echo "         ./infrastructure/scripts/build-and-load.sh"
echo "    2. Deploy the application:"
echo "         ./infrastructure/scripts/deploy.sh"
echo "    3. Set up the OTel telemetry stack:"
echo "         ./infrastructure/scripts/setup-telemetry.sh"
