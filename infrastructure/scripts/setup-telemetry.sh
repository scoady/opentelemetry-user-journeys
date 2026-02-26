#!/usr/bin/env bash
# setup-telemetry.sh — Deploy cert-manager and the OpenTelemetry Operator via Helm,
#                      then apply the OTel Collector CR from k8s manifests.
#
# Before running, populate your vendor credentials:
#   kubectl create secret generic otel-vendor-credentials \
#     -n observability \
#     --from-literal=GRAFANA_AUTH=<base64(instanceId:apiKey)>
#
# Run once after setup-cluster.sh. Safe to re-run — all steps are idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELM_DIR="${ROOT_DIR}/infrastructure/helm"
K8S_TELEMETRY="${ROOT_DIR}/infrastructure/k8s/telemetry"

CERT_MANAGER_CHART_VERSION="v1.19.4"
OTEL_OPERATOR_CHART_VERSION="0.106.0"

# ── 1. cert-manager ───────────────────────────────────────────────────────────
echo ">>> Installing cert-manager ${CERT_MANAGER_CHART_VERSION} via Helm…"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "${CERT_MANAGER_CHART_VERSION}" \
  --values "${HELM_DIR}/cert-manager/values.yaml" \
  --wait

# ── 2. OpenTelemetry Operator ─────────────────────────────────────────────────
echo ""
echo ">>> Installing OpenTelemetry Operator ${OTEL_OPERATOR_CHART_VERSION} via Helm…"
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system \
  --create-namespace \
  --version "${OTEL_OPERATOR_CHART_VERSION}" \
  --values "${HELM_DIR}/opentelemetry-operator/values.yaml" \
  --wait

# ── 3. Collector CR ───────────────────────────────────────────────────────────
echo ""
echo ">>> Deploying OpenTelemetry Collector…"
kubectl apply -f "${K8S_TELEMETRY}/namespace.yaml"
kubectl apply -f "${K8S_TELEMETRY}/collector/"

echo "  Waiting for collector to be ready…"
kubectl wait --for=condition=available deployment/otel-collector \
  -n observability \
  --timeout=120s

# ── 4. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "✓ OTel Collector ready!"
echo ""
echo "  Collector endpoints (reachable from any pod in the cluster):"
echo "    OTLP gRPC:  otel-collector.observability.svc.cluster.local:4317"
echo "    OTLP HTTP:  otel-collector.observability.svc.cluster.local:4318"
echo ""
echo "  To enable vendor export:"
echo "    1. Populate the secret (once per cluster):"
echo "         kubectl create secret generic otel-vendor-credentials \\"
echo "           -n observability \\"
echo "           --from-literal=GRAFANA_AUTH=\$(printf '<instanceId>:<apiKey>' | base64)"
echo "    2. kubectl apply -f infrastructure/k8s/telemetry/collector/"
echo "       kubectl rollout restart deployment/otel-collector -n observability"
echo ""
kubectl get pods -n observability
