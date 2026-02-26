#!/usr/bin/env bash
# build-and-load.sh — Full update cycle: build images, load into kind,
#                     upgrade Helm release, restart pods.
#
# Use this script whenever you change application code OR k8s manifests.
# For a first-time deploy on a fresh cluster, run deploy.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHART_DIR="${ROOT_DIR}/infrastructure/helm/techmart"
VALUES_FILE="${CHART_DIR}/values.yaml"

# ── 1. Build images ───────────────────────────────────────────────────────────
echo ">>> Building Docker images…"

echo "  [1/2] Building API image (webstore/api:latest)…"
docker build -t webstore/api:latest "${ROOT_DIR}/api"

echo "  [2/2] Building Frontend image (webstore/frontend:latest)…"
docker build -t webstore/frontend:latest "${ROOT_DIR}/frontend"

# ── 2. Load into kind ─────────────────────────────────────────────────────────
echo ""
echo ">>> Loading images into kind cluster 'techmart'…"
kind load docker-image webstore/api:latest      --name techmart
kind load docker-image webstore/frontend:latest --name techmart

# ── 3. Helm upgrade (picks up manifest changes) ───────────────────────────────
if kubectl get namespace webstore &>/dev/null; then
  echo ""
  echo ">>> Upgrading Helm release…"
  helm upgrade techmart "${CHART_DIR}" \
    --namespace webstore \
    --values "${VALUES_FILE}" \
    --wait \
    --timeout 3m

  # kind uses imagePullPolicy: Never — running pods hold the old image layer
  # until replaced. Force a rollout so new pods start with the freshly loaded image.
  echo ""
  echo ">>> Restarting app deployments to pick up new images…"
  kubectl rollout restart deployment/api deployment/frontend -n webstore
  kubectl rollout status  deployment/api      -n webstore --timeout=120s
  kubectl rollout status  deployment/frontend -n webstore --timeout=120s

  echo ""
  echo "✓ Update complete. Open http://localhost in your browser."
else
  echo ""
  echo "✓ Images loaded."
  echo "  Namespace 'webstore' not found — run deploy.sh for a first-time deploy."
fi
