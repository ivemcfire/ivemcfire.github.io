#!/usr/bin/env bash
# setup-preempt.sh — seeds a FULL node so PriorityClass preemption actually fires.
#
# SAFE TO READ. Seeder, not a fault injection.
#
# Sizes the filler workload from the node's REAL allocatable memory, so the node
# ends up genuinely near-full. A high-priority Pod requesting the printed amount
# then cannot schedule without EVICTING filler Pods. Without this, preemption
# never triggers and the task looks broken when it isn't.
#
# Usage:
#   bash setup-preempt.sh          # seed
#   bash setup-preempt.sh restore  # remove everything it created

set -euo pipefail

NS="${NS:-batch}"

banner() { printf '\n== %s ==\n' "$1"; }

if [[ "${1:-}" == "restore" ]]; then
  banner "removing scenario"
  kubectl delete ns "$NS" --ignore-not-found --wait=false
  kubectl delete priorityclass low-priority --ignore-not-found
  kubectl delete priorityclass high-priority --ignore-not-found
  echo "done."
  exit 0
fi

banner "context"
kubectl config current-context || true

# Pick the node with the most allocatable memory that will actually accept Pods.
# NOTE: KodeKloud names control planes "clusterN-controlplane" (no hyphen), so a
# naive `grep -v control-plane` does NOT exclude them. Prefer a non-controlplane
# node, but fall back to whatever exists (single-node labs are fine for this).
NODE="$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers \
        | grep -vi 'controlplane\|control-plane' | head -1 || true)"
if [[ -z "$NODE" ]]; then
  NODE="$(kubectl get nodes -o custom-columns=NAME:.metadata.name --no-headers | head -1)"
  echo "note: no dedicated worker; using $NODE (single-node lab is fine here)"
fi
banner "target node: $NODE"

RAW="$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.memory}')"
case "$RAW" in
  *Ki) ALLOC_MI=$(( ${RAW%Ki} / 1024 )) ;;
  *Mi) ALLOC_MI=${RAW%Mi} ;;
  *Gi) ALLOC_MI=$(( ${RAW%Gi} * 1024 )) ;;
  *)   ALLOC_MI=4096 ;;
esac

REPLICAS=6
FILLER_MI=$(( ALLOC_MI * 60 / 100 / REPLICAS ))   # filler occupies ~60% of the node
URGENT_MI=$(( ALLOC_MI * 25 / 100 ))              # 2 x 25% = 50% -> cannot fit alongside

echo "allocatable : $RAW  (~${ALLOC_MI}Mi)"
echo "filler      : ${REPLICAS} x ${FILLER_MI}Mi  (~60%)"
echo "urgent needs: 2 x ${URGENT_MI}Mi  (~50%)  -> preemption required"

banner "namespace $NS"
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -

banner "low-priority class"
kubectl create priorityclass low-priority --value=1000 --global-default=false \
  --description="Batch filler" --dry-run=client -o yaml | kubectl apply -f -

banner "filler workload pinned to $NODE"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: filler
  namespace: $NS
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: filler
  template:
    metadata:
      labels:
        app: filler
    spec:
      priorityClassName: low-priority
      nodeName: $NODE
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          requests:
            memory: "${FILLER_MI}Mi"
            cpu: "20m"
EOF

banner "waiting for filler to settle"
sleep 10
kubectl get pod -n "$NS" -o wide

cat <<EOF

Seeded.
  Namespace : $NS
  Node      : $NODE
  Class     : low-priority (value 1000)
  Filler    : ${REPLICAS} Pods x ${FILLER_MI}Mi

>>> Build the high-priority Deployment with memory request: ${URGENT_MI}Mi
    Two replicas at that size CANNOT fit until filler Pods are evicted.

Cleanup: bash setup-preempt.sh restore
EOF
