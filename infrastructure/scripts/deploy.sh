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

echo ""
echo "✓ TechMart is deployed!"
echo ""
echo "  Open http://localhost in your browser."
echo ""
kubectl get pods -n webstore
