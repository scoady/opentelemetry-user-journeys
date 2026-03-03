#!/usr/bin/env bash
# build-and-load.sh — Full update cycle: build images, load into kind,
#                     upgrade Helm release.
#
# Use this script whenever you change application code OR k8s manifests.
# For a first-time deploy on a fresh cluster, run deploy.sh instead.
#
# Each run tags images with the current git SHA so Helm detects a spec
# change and triggers a rolling update automatically — no kubectl rollout
# restart needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHART_DIR="${ROOT_DIR}/helm"
VALUES_FILE="${CHART_DIR}/values.yaml"

# ── Image tag ─────────────────────────────────────────────────────────────────
# Use the short git SHA as the tag. Append -dev if there are uncommitted changes
# so each local iteration gets a unique tag even before committing.
TAG="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain 2>/dev/null)" ]]; then
  TAG="${TAG}-dev"
fi
echo ">>> Image tag: ${TAG}"

# ── 1. Build images ───────────────────────────────────────────────────────────
echo ""
echo ">>> Building Docker images…"

echo "  [1/4] scoady/api:${TAG}"
docker build -t "scoady/api:${TAG}" "${ROOT_DIR}/api"

echo "  [2/4] scoady/inventory-svc:${TAG}"
docker build -t "scoady/inventory-svc:${TAG}" "${ROOT_DIR}/inventory-svc"

echo "  [3/4] scoady/frontend:${TAG}"
docker build -t "scoady/frontend:${TAG}" "${ROOT_DIR}/frontend"

echo "  [4/4] scoady/product-worker:${TAG}"
docker build -t "scoady/product-worker:${TAG}" "${ROOT_DIR}/product-worker"

# ── 2. Load into kind ─────────────────────────────────────────────────────────
echo ""
echo ">>> Loading images into kind cluster 'scoady'…"
kind load docker-image "scoady/api:${TAG}"            --name scoady
kind load docker-image "scoady/inventory-svc:${TAG}"  --name scoady
kind load docker-image "scoady/frontend:${TAG}"       --name scoady
kind load docker-image "scoady/product-worker:${TAG}" --name scoady

# ── 3. Helm upgrade ───────────────────────────────────────────────────────────
# Passing a new image tag changes the Deployment spec — Helm's --wait handles
# the rolling update and readiness checks. No kubectl rollout restart needed.
if kubectl get namespace scoady &>/dev/null; then
  echo ""
  echo ">>> Upgrading Helm release (tag=${TAG})…"
  helm upgrade scoady "${CHART_DIR}" \
    --namespace scoady \
    --values "${VALUES_FILE}" \
    --set "api.image.tag=${TAG}" \
    --set "inventorySvc.image.tag=${TAG}" \
    --set "frontend.image.tag=${TAG}" \
    --set "productWorker.image.tag=${TAG}" \
    --wait \
    --timeout 3m

  echo ""
  echo "✓ Update complete. Open http://scoady.local in your browser."
else
  echo ""
  echo "✓ Images loaded."
  echo "  Namespace 'scoady' not found — run deploy.sh for a first-time deploy."
fi
