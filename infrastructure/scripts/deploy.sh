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
#
# NOTE: If you previously deployed with raw `kubectl apply` manifests, remove
# those resources first to avoid ownership conflicts:
#   kubectl delete all,configmap,secret,ingress,pvc -n webstore --all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHART_DIR="${ROOT_DIR}/infrastructure/helm/techmart"
VALUES_FILE="${CHART_DIR}/values.yaml"

echo ">>> Deploying TechMart via Helm…"

helm upgrade --install techmart "${CHART_DIR}" \
  --namespace webstore \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 5m

echo ""
echo ">>> Waiting for all pods to be ready…"
kubectl wait --for=condition=ready pod \
  --selector app.kubernetes.io/instance=techmart \
  -n webstore \
  --timeout=120s

# Poll /api/health until we get JSON back. The frontend nginx proxies /api to
# the API service, so a JSON response here confirms the full stack is live:
# ingress → frontend nginx → API → Postgres.
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
echo "  Grafana dashboards: import from infrastructure/grafana/dashboards/"
echo "    slo-overview.json   — all CUJs at a glance"
echo "    checkout-slo.json   — checkout deep-dive with error budget"
echo ""
echo "  To update after code or manifest changes:"
echo "    ./infrastructure/scripts/build-and-load.sh"
echo ""
kubectl get pods -n webstore
