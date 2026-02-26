#!/usr/bin/env bash
# setup-telemetry.sh — Deploy cert-manager and the OpenTelemetry Operator via
#                      Helm, then apply the Collector CR and Instrumentation CR.
#
# Before running, create the vendor credentials secret (once per cluster):
#
#   kubectl create secret generic otel-vendor-credentials \
#     -n observability \
#     --from-literal=GRAFANA_INSTANCE_ID=<your-stack-id> \
#     --from-literal=GRAFANA_API_KEY=<glc_...token>
#
#   Your stack ID and API key are found at:
#   Grafana Cloud → <stack> → OpenTelemetry → Configure
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

# Apply collector config (everything except the secret — handled below).
kubectl apply -f "${K8S_TELEMETRY}/collector/collector.yaml"

# Only create the credentials secret if it doesn't already exist.
# This prevents wiping real credentials on re-runs.
if kubectl get secret otel-vendor-credentials -n observability &>/dev/null; then
  echo "  Secret 'otel-vendor-credentials' already exists — skipping."
else
  echo "  Creating placeholder credentials secret…"
  kubectl apply -f "${K8S_TELEMETRY}/collector/secret.yaml"
  echo ""
  echo "  ⚠️  Credentials secret is empty. Populate it before the collector"
  echo "     can export to Grafana Cloud:"
  echo ""
  echo "    kubectl create secret generic otel-vendor-credentials \\"
  echo "      -n observability --dry-run=client -o yaml \\"
  echo "      --from-literal=GRAFANA_INSTANCE_ID=<your-stack-id> \\"
  echo "      --from-literal=GRAFANA_API_KEY=<glc_...token> \\"
  echo "    | kubectl apply -f -"
  echo ""
  echo "  Then restart the collector:"
  echo "    kubectl rollout restart deployment/otel-collector -n observability"
fi

echo "  Waiting for collector to be ready…"
kubectl wait --for=condition=available deployment/otel-collector \
  -n observability \
  --timeout=120s

# ── 4. Summary ────────────────────────────────────────────────────────────────
# NOTE: The Instrumentation CR (instrumentation.yaml) targets the webstore
# namespace and is applied by deploy.sh after the Helm install creates it.
echo ""
echo "✓ OTel telemetry stack ready!"
echo ""
echo "  Collector endpoints (reachable from any pod in the cluster):"
echo "    OTLP gRPC:  otel-collector.observability.svc.cluster.local:4317"
echo "    OTLP HTTP:  otel-collector.observability.svc.cluster.local:4318"
echo ""
kubectl get pods -n observability
