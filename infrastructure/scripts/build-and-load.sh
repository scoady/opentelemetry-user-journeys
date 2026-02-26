#!/usr/bin/env bash
# build-and-load.sh — Full update cycle: build images, load into kind,
#                     re-apply manifests, restart pods.
#
# Use this script whenever you change application code OR k8s manifests.
# For a first-time deploy on a fresh cluster, run deploy.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K8S_DIR="${ROOT_DIR}/infrastructure/k8s"

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

# ── 3. Apply manifests + restart pods ─────────────────────────────────────────
if kubectl get namespace webstore &>/dev/null; then
  echo ""
  echo ">>> Applying k8s manifests…"

  kubectl apply -f "${K8S_DIR}/namespace.yaml"

  echo "  database tier…"
  kubectl apply -f "${K8S_DIR}/database/secret.yaml"
  kubectl apply -f "${K8S_DIR}/database/pvc.yaml"
  kubectl apply -f "${K8S_DIR}/database/configmap.yaml"
  kubectl apply -f "${K8S_DIR}/database/deployment.yaml"
  kubectl apply -f "${K8S_DIR}/database/service.yaml"

  echo "  api tier…"
  kubectl apply -f "${K8S_DIR}/api/configmap.yaml"
  kubectl apply -f "${K8S_DIR}/api/deployment.yaml"
  kubectl apply -f "${K8S_DIR}/api/service.yaml"

  echo "  frontend tier…"
  kubectl apply -f "${K8S_DIR}/frontend/deployment.yaml"
  kubectl apply -f "${K8S_DIR}/frontend/service.yaml"
  kubectl apply -f "${K8S_DIR}/frontend/ingress.yaml"

  echo "  traffic generator…"
  kubectl apply -f "${K8S_DIR}/traffic/configmap.yaml"
  kubectl apply -f "${K8S_DIR}/traffic/deployment.yaml"

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
