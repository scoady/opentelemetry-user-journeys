#!/usr/bin/env bash
# deploy.sh — Apply all Kubernetes manifests to the webstore namespace
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/../k8s" && pwd)"

echo ">>> Applying Kubernetes manifests…"

# Namespace first
kubectl apply -f "${K8S_DIR}/namespace.yaml"

# Database tier
echo "  Applying database tier…"
kubectl apply -f "${K8S_DIR}/database/secret.yaml"
kubectl apply -f "${K8S_DIR}/database/pvc.yaml"
kubectl apply -f "${K8S_DIR}/database/configmap.yaml"
kubectl apply -f "${K8S_DIR}/database/deployment.yaml"
kubectl apply -f "${K8S_DIR}/database/service.yaml"

echo "  Waiting for PostgreSQL to be ready…"
kubectl rollout status deployment/postgres -n webstore --timeout=120s

# API tier
echo "  Applying API tier…"
kubectl apply -f "${K8S_DIR}/api/configmap.yaml"
kubectl apply -f "${K8S_DIR}/api/deployment.yaml"
kubectl apply -f "${K8S_DIR}/api/service.yaml"

echo "  Waiting for API to be ready…"
kubectl rollout status deployment/api -n webstore --timeout=120s

# Frontend tier
echo "  Applying frontend tier…"
kubectl apply -f "${K8S_DIR}/frontend/deployment.yaml"
kubectl apply -f "${K8S_DIR}/frontend/service.yaml"
kubectl apply -f "${K8S_DIR}/frontend/ingress.yaml"

echo "  Waiting for frontend to be ready…"
kubectl rollout status deployment/frontend -n webstore --timeout=120s

# The ingress controller reloads its nginx config asynchronously after the
# ingress resource is applied. kubectl rollout status only confirms pods are
# running — not that routing is live. Poll /api/health until we get JSON back,
# which confirms the /api prefix is actually wired to the API service.
echo "  Waiting for ingress routing to propagate…"
for i in $(seq 1 30); do
  ct=$(curl -s -o /dev/null -w "%{content_type}" http://localhost/api/health 2>/dev/null || true)
  if [[ "$ct" == *"application/json"* ]]; then
    echo "  Ingress confirmed: /api is routing to the API service."
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "  Warning: ingress may still be propagating. If you see an error in the browser, wait a few seconds and refresh."
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
kubectl get pods -n webstore
