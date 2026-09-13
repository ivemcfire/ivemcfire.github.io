#!/usr/bin/env bash
# CKA drill seed — StorageClass default swap + expansion + new class.
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-sc-default.sh          # seed
#         bash setup-sc-default.sh restore  # tear down
# Requires: kubectl, an existing StorageClass `local-path` (rancher.io/local-path) — Killercoda playground.
set -u

STATE=/tmp/.cka-sc-default-state
ANN=storageclass.kubernetes.io/is-default-class

if [ "${1:-}" = "restore" ]; then
  kubectl delete -f "https://ivemcfire.github.io/cka/scenarios/sc-probe.yaml" --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl delete sc legacy-hdd slow-sc --ignore-not-found >/dev/null 2>&1
  if [ -f "$STATE" ]; then
    . "$STATE"
    kubectl annotate sc local-path "$ANN=${ORIG_DEFAULT:-true}" --overwrite >/dev/null 2>&1
    if [ -n "${ORIG_EXPAND:-}" ]; then
      kubectl patch sc local-path -p "{\"allowVolumeExpansion\": ${ORIG_EXPAND}}" >/dev/null 2>&1
    else
      kubectl patch sc local-path --type=json -p '[{"op":"remove","path":"/allowVolumeExpansion"}]' >/dev/null 2>&1
    fi
    rm -f "$STATE"
  fi
  echo "restored."
  exit 0
fi

if ! kubectl get sc local-path >/dev/null 2>&1; then
  echo "GATE: no StorageClass local-path on this cluster — load the Killercoda playground." >&2
  exit 1
fi

if [ ! -f "$STATE" ]; then
  {
    echo "ORIG_DEFAULT=$(kubectl get sc local-path -o jsonpath="{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}")"
    echo "ORIG_EXPAND=$(kubectl get sc local-path -o jsonpath='{.allowVolumeExpansion}')"
  } > "$STATE"
fi

kubectl annotate sc local-path "$ANN-" >/dev/null 2>&1
kubectl patch sc local-path --type=json -p '[{"op":"remove","path":"/allowVolumeExpansion"}]' >/dev/null 2>&1

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: legacy-hdd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF

echo "seeded."
