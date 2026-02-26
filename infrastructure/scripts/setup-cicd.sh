#!/usr/bin/env bash
# setup-cicd.sh — Deploy the in-cluster Docker registry and Jenkins CI/CD server.
#
# Prerequisites (run in order):
#   1. ./infrastructure/scripts/setup-cluster.sh — kind cluster + Helm repos
#      (jenkins and twuni repos are added there)
#   2. THIS SCRIPT
#
# After this script:
#   Registry: registry.registry.svc.cluster.local:5000  (in-cluster only)
#   Jenkins:  http://jenkins.localhost
#
# Safe to re-run — all steps are idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HELM_DIR="${ROOT_DIR}/infrastructure/helm"
K8S_CICD_DIR="${ROOT_DIR}/infrastructure/k8s/cicd"

JENKINS_CHART_VERSION="5.8.3"

KIND_NODES=(techmart-control-plane techmart-worker techmart-worker2)
REGISTRY_HOST="registry.registry.svc.cluster.local"
REGISTRY_PORT="5000"
REGISTRY_ADDR="${REGISTRY_HOST}:${REGISTRY_PORT}"

# ── 1. Add Helm repos (idempotent) ────────────────────────────────────────────
echo ">>> Ensuring jenkins Helm repo is available…"
helm repo add jenkins  https://charts.jenkins.io  --force-update
helm repo update

# ── 2. Deploy Docker Registry ─────────────────────────────────────────────────
echo ""
echo ">>> Deploying Docker Registry (custom chart)…"
helm upgrade --install registry "${HELM_DIR}/registry" \
  --namespace registry \
  --create-namespace \
  --values "${HELM_DIR}/registry/values.yaml" \
  --wait \
  --timeout 3m

echo ">>> Waiting for registry deployment to be available…"
kubectl wait --for=condition=available deployment/registry \
  --namespace registry \
  --timeout=120s

# ── 3. Resolve registry ClusterIP ─────────────────────────────────────────────
echo ""
echo ">>> Resolving registry ClusterIP…"
REGISTRY_IP=$(kubectl get svc registry -n registry -o jsonpath='{.spec.clusterIP}')
echo "  ClusterIP: ${REGISTRY_IP}"

# ── 4. Patch containerd on each kind node ─────────────────────────────────────
# kind nodes are Docker containers. We exec into each to:
#   a) Add an /etc/hosts entry so containerd can resolve the registry hostname
#      (cluster DNS is not available to the node's containerd daemon).
#   b) Write a hosts.toml for the registry, allowing plain-HTTP pull.
#   c) Send SIGHUP to containerd to reload config without restarting.
echo ""
echo ">>> Patching containerd on kind nodes for insecure registry access…"

for NODE in "${KIND_NODES[@]}"; do
  echo "  Patching node: ${NODE}"

  # 4a. /etc/hosts — filter out any stale entry via a temp file (sed -i fails on
  #      kind node overlayfs due to rename restrictions on /etc), then append.
  docker exec "${NODE}" sh -c \
    "grep -v '${REGISTRY_HOST}' /etc/hosts > /tmp/hosts.new && \
     cp /tmp/hosts.new /etc/hosts && \
     echo '${REGISTRY_IP} ${REGISTRY_HOST}' >> /etc/hosts"

  # 4b. Create the per-registry certs.d directory.
  docker exec "${NODE}" mkdir -p \
    "/etc/containerd/certs.d/${REGISTRY_ADDR}"

  # 4c. Write hosts.toml — skip TLS, allow plain HTTP.
  docker exec "${NODE}" sh -c "cat > /etc/containerd/certs.d/${REGISTRY_ADDR}/hosts.toml << 'TOML'
server = \"http://${REGISTRY_ADDR}\"

[host.\"http://${REGISTRY_ADDR}\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  skip_verify = true
TOML"

  # 4d. Reload containerd (SIGHUP). No pod disruption.
  docker exec "${NODE}" pkill -HUP containerd
  echo "    containerd reloaded on ${NODE}."
done

# ── 5. Sanity-check registry is reachable from a node ─────────────────────────
echo ""
echo ">>> Verifying registry is reachable from control-plane node…"
docker exec techmart-control-plane \
  curl -sf "http://${REGISTRY_ADDR}/v2/_catalog" \
  && echo "  Registry OK: $(docker exec techmart-control-plane curl -s http://${REGISTRY_ADDR}/v2/_catalog)" \
  || echo "  WARNING: registry not yet reachable — it may still be starting. Continuing…"

# ── 6. Apply Jenkins deployer RBAC ────────────────────────────────────────────
echo ""
echo ">>> Applying Jenkins deployer RBAC…"
kubectl apply -f "${K8S_CICD_DIR}/rbac.yaml"

# ── 7. Deploy Jenkins ─────────────────────────────────────────────────────────
echo ""
echo ">>> Deploying Jenkins (jenkins/jenkins v${JENKINS_CHART_VERSION})…"
helm upgrade --install jenkins jenkins/jenkins \
  --namespace cicd \
  --create-namespace \
  --version "${JENKINS_CHART_VERSION}" \
  --set controller.image.tag=lts-jdk21 \
  --values "${HELM_DIR}/jenkins/values.yaml" \
  --wait \
  --timeout 10m

echo ">>> Waiting for Jenkins controller to be ready…"
kubectl wait --for=condition=available deployment/jenkins \
  --namespace cicd \
  --timeout=300s

# ── 8. Add jenkins.localhost to /etc/hosts ────────────────────────────────────
echo ""
if grep -q "jenkins.localhost" /etc/hosts 2>/dev/null; then
  echo ">>> /etc/hosts already has jenkins.localhost — skipping."
else
  echo ">>> Adding jenkins.localhost to /etc/hosts (requires sudo)…"
  echo "    Run:  echo '127.0.0.1 jenkins.localhost' | sudo tee -a /etc/hosts"
  echo "    (or approve the sudo prompt)"
  echo "127.0.0.1 jenkins.localhost" | sudo tee -a /etc/hosts 2>/dev/null \
    || echo "  Skipped (no sudo available). Add manually: 127.0.0.1 jenkins.localhost"
fi

# ── 9. Print summary ──────────────────────────────────────────────────────────
JENKINS_PASS=$(kubectl get secret jenkins -n cicd \
  -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d || echo "<not ready yet>")

echo ""
echo "✓ CI/CD stack is ready!"
echo ""
echo "  Registry: http://${REGISTRY_ADDR}  (in-cluster only)"
echo "  Jenkins:  http://jenkins.localhost"
echo ""
echo "  Jenkins admin credentials:"
echo "    Username: admin"
echo "    Password: ${JENKINS_PASS}"
echo ""
echo "  Pipeline jobs are pre-configured via JCasC:"
echo "    techmart-build  → ci/build.Jenkinsfile   (polls /src/repo every 5 min)"
echo "    techmart-deploy → ci/deploy.Jenkinsfile  (parameterized: IMAGE_TAG)"
echo ""
echo "  Trigger a build manually:"
echo "    Open http://jenkins.localhost → techmart-build → Build Now"
echo ""
echo "  Inspect registry contents:"
echo "    kubectl exec -n registry deploy/registry -- \\"
echo "      wget -qO- http://localhost:5000/v2/_catalog"
echo ""
kubectl get pods -n registry
echo ""
kubectl get pods -n cicd
