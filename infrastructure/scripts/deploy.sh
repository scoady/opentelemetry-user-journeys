#!/usr/bin/env bash
# deploy.sh — First-time deploy of the full TechMart stack (app + traffic generator).
#
# Prerequisites (run in order on a fresh cluster):
#   1. ./infrastructure/scripts/setup-cluster.sh   — kind cluster + Helm repos
#   2. ./infrastructure/scripts/build-and-load.sh  — build + load Docker images
#   3. ./infrastructure/scripts/setup-telemetry.sh — cert-manager + OTel Operator + Collector
#   4. THIS SCRIPT                                 — namespaced k8s resources
#
# For subsequent code or manifest changes, use build-and-load.sh instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/../k8s" && pwd)"

echo ">>> Applying Kubernetes manifests…"

# ── Namespace ─────────────────────────────────────────────────────────────────
kubectl apply -f "${K8S_DIR}/namespace.yaml"

# ── Database tier ─────────────────────────────────────────────────────────────
echo "  Applying database tier…"
kubectl apply -f "${K8S_DIR}/database/secret.yaml"
kubectl apply -f "${K8S_DIR}/database/pvc.yaml"
kubectl apply -f "${K8S_DIR}/database/configmap.yaml"
kubectl apply -f "${K8S_DIR}/database/deployment.yaml"
kubectl apply -f "${K8S_DIR}/database/service.yaml"

echo "  Waiting for PostgreSQL to be ready…"
kubectl rollout status deployment/postgres -n webstore --timeout=120s

# ── API tier ──────────────────────────────────────────────────────────────────
echo "  Applying API tier…"
kubectl apply -f "${K8S_DIR}/api/configmap.yaml"
kubectl apply -f "${K8S_DIR}/api/deployment.yaml"
kubectl apply -f "${K8S_DIR}/api/service.yaml"

echo "  Waiting for API to be ready…"
kubectl rollout status deployment/api -n webstore --timeout=120s

# ── Frontend tier ─────────────────────────────────────────────────────────────
echo "  Applying frontend tier…"
kubectl apply -f "${K8S_DIR}/frontend/deployment.yaml"
kubectl apply -f "${K8S_DIR}/frontend/service.yaml"
kubectl apply -f "${K8S_DIR}/frontend/ingress.yaml"

echo "  Waiting for frontend to be ready…"
kubectl rollout status deployment/frontend -n webstore --timeout=120s

# ── Traffic generator (k6) ────────────────────────────────────────────────────
echo "  Applying traffic generator (k6 @ 5 req/s)…"
kubectl apply -f "${K8S_DIR}/traffic/configmap.yaml"
kubectl apply -f "${K8S_DIR}/traffic/deployment.yaml"

# ── Health check ──────────────────────────────────────────────────────────────
echo "  Waiting for full stack to be reachable…"
for i in $(seq 1 30); do
  ct=$(curl -s -o /dev/null -w "%{content_type}" http://localhost/api/health 2>/dev/null || true)
  if [[ "$ct" == *"application/json"* ]]; then
    echo "  Stack confirmed healthy."
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "  Warning: stack may still be starting. Wait a few seconds and refresh."
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
echo "  Grafana dashboards: import the JSON files from infrastructure/grafana/dashboards/"
echo "    slo-overview.json   — all CUJs at a glance"
echo "    checkout-slo.json   — checkout deep-dive with error budget"
echo ""
echo "  To update after code or manifest changes:"
echo "    ./infrastructure/scripts/build-and-load.sh"
echo ""
kubectl get pods -n webstore
