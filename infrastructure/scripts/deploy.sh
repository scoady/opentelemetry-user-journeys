#!/usr/bin/env bash
# deploy.sh — First-time deploy of the full TechMart stack via Helm.
#
# Prerequisites (run in order on a fresh cluster):
#   1. ./infrastructure/scripts/setup-cluster.sh   — kind cluster + Helm repos
#   2. ./infrastructure/scripts/build-and-load.sh  — build + load Docker images
#   3. ./infrastructure/scripts/setup-telemetry.sh — cert-manager + OTel Operator + Collector
#   4. THIS SCRIPT                                 — Helm install of the app
#
# For subsequent code or manifest changes, use build-and-load.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHART_DIR="${ROOT_DIR}/infrastructure/helm/techmart"
VALUES_FILE="${CHART_DIR}/values.yaml"

# Use the same SHA tag that build-and-load.sh produced for these images.
TAG="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain 2>/dev/null)" ]]; then
  TAG="${TAG}-dev"
fi
echo ">>> Deploying TechMart (tag=${TAG})…"

# The Instrumentation CR is a pre-install hook inside the chart — it is created
# before app pods so the OTel webhook has a CR to resolve at pod admission time.
helm upgrade --install techmart "${CHART_DIR}" \
  --namespace webstore \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --set "api.image.tag=${TAG}" \
  --set "inventorySvc.image.tag=${TAG}" \
  --set "frontend.image.tag=${TAG}" \
  --wait \
  --timeout 5m

# One rollout restart is still needed after a fresh install: the OTel operator's
# informer cache may not have synced the newly-created Instrumentation CR by the
# time the admission webhook fired for the initial pods. The restart triggers a
# second admission pass once the cache is warm.
echo ""
echo ">>> Restarting instrumented pods so OTel webhook picks up the Instrumentation CR…"
kubectl rollout restart deployment/api deployment/inventory-svc -n webstore
kubectl rollout status  deployment/api           -n webstore --timeout=120s
kubectl rollout status  deployment/inventory-svc -n webstore --timeout=120s

# Poll /api/health until the full stack is reachable.
echo ""
echo ">>> Waiting for full stack to be reachable…"
for i in $(seq 1 30); do
  ct=$(curl -s -o /dev/null -w "%{content_type}" http://localhost/api/health 2>/dev/null || true)
  if [[ "$ct" == *"application/json"* ]]; then
    echo "    Stack confirmed healthy."
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "    Warning: stack may still be starting. Wait a few seconds and refresh."
  else
    printf "\r    attempt %d/30 — not ready yet…" "$i"
    sleep 2
  fi
done

echo ""
echo "✓ TechMart is deployed!"
echo ""
echo "  Open http://localhost in your browser."
echo ""
echo "  Grafana dashboards: deploy via Terraform"
echo "    cd terraform && terraform init && terraform apply"
echo ""
echo "  To update after code or manifest changes:"
echo "    ./infrastructure/scripts/build-and-load.sh"
echo ""
kubectl get pods -n webstore
