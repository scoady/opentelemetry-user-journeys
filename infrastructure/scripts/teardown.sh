#!/usr/bin/env bash
# teardown.sh — Delete the kind cluster entirely
set -euo pipefail

echo ">>> Deleting kind cluster 'techmart'…"
kind delete cluster --name techmart
echo "✓ Cluster deleted."
