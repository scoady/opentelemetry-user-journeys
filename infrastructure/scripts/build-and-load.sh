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
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHART_DIR="${ROOT_DIR}/infrastructure/helm/techmart"
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

echo "  [1/3] webstore/api:${TAG}"
docker build -t "webstore/api:${TAG}" "${ROOT_DIR}/api"

echo "  [2/3] webstore/inventory-svc:${TAG}"
docker build -t "webstore/inventory-svc:${TAG}" "${ROOT_DIR}/inventory-svc"

echo "  [3/3] webstore/frontend:${TAG}"
docker build -t "webstore/frontend:${TAG}" "${ROOT_DIR}/frontend"

# ── 2. Load into kind ─────────────────────────────────────────────────────────
echo ""
echo ">>> Loading images into kind cluster 'techmart'…"
kind load docker-image "webstore/api:${TAG}"           --name techmart
kind load docker-image "webstore/inventory-svc:${TAG}" --name techmart
kind load docker-image "webstore/frontend:${TAG}"      --name techmart

# ── 3. Helm upgrade ───────────────────────────────────────────────────────────
# Passing a new image tag changes the Deployment spec — Helm's --wait handles
# the rolling update and readiness checks. No kubectl rollout restart needed.
if kubectl get namespace webstore &>/dev/null; then
  echo ""
  echo ">>> Upgrading Helm release (tag=${TAG})…"
  helm upgrade techmart "${CHART_DIR}" \
    --namespace webstore \
    --values "${VALUES_FILE}" \
    --set "api.image.tag=${TAG}" \
    --set "inventorySvc.image.tag=${TAG}" \
    --set "frontend.image.tag=${TAG}" \
    --wait \
    --timeout 3m

  echo ""
  echo "✓ Update complete. Open http://localhost in your browser."
else
  echo ""
  echo "✓ Images loaded."
  echo "  Namespace 'webstore' not found — run deploy.sh for a first-time deploy."
fi
