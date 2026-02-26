#!/usr/bin/env bash
# setup-telemetry.sh — Install cert-manager, the OpenTelemetry Operator,
#                      and deploy the telemetry pipeline (collector + Jaeger).
#
# Run once after setup-cluster.sh. Safe to re-run — all steps are idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K8S_TELEMETRY="${ROOT_DIR}/infrastructure/k8s/telemetry"

CERT_MANAGER_VERSION="v1.19.4"
OTEL_OPERATOR_VERSION="v0.145.0"

# ── 1. cert-manager (required by the OTel operator's webhooks) ────────────────
echo ">>> Installing cert-manager ${CERT_MANAGER_VERSION}…"
kubectl apply -f \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "  Waiting for cert-manager to be ready…"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=webhook \
  -n cert-manager \
  --timeout=120s

# ── 2. OpenTelemetry Operator ─────────────────────────────────────────────────
echo ""
echo ">>> Installing OpenTelemetry Operator ${OTEL_OPERATOR_VERSION}…"
kubectl apply -f \
  "https://github.com/open-telemetry/opentelemetry-operator/releases/download/${OTEL_OPERATOR_VERSION}/opentelemetry-operator.yaml"

echo "  Waiting for operator to be ready…"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=opentelemetry-operator \
  -n opentelemetry-operator-system \
  --timeout=180s

# ── 3. Observability namespace + Jaeger ───────────────────────────────────────
echo ""
echo ">>> Deploying telemetry stack…"
kubectl apply -f "${K8S_TELEMETRY}/namespace.yaml"

echo "  Deploying Jaeger…"
kubectl apply -f "${K8S_TELEMETRY}/jaeger/"
kubectl rollout status deployment/jaeger -n observability --timeout=120s

# ── 4. OpenTelemetry Collector ────────────────────────────────────────────────
echo "  Deploying OpenTelemetry Collector…"
kubectl apply -f "${K8S_TELEMETRY}/collector/"

echo "  Waiting for collector to be ready…"
kubectl wait --for=condition=available deployment/otel-collector \
  -n observability \
  --timeout=120s

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "✓ Telemetry pipeline ready!"
echo ""
echo "  Jaeger UI:    http://localhost/jaeger"
echo ""
echo "  Collector endpoints (reachable from any pod in the cluster):"
echo "    OTLP gRPC:  otel-collector.observability.svc.cluster.local:4317"
echo "    OTLP HTTP:  otel-collector.observability.svc.cluster.local:4318"
echo ""
kubectl get pods -n observability
