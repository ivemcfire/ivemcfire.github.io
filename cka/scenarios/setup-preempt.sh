#!/usr/bin/env bash
# setup-preempt.sh — seeds a FULL node so PriorityClass preemption actually fires.
#
# SAFE TO READ. Seeder, not a fault injection.
#
# Creates ns "batch" with a low-priority PriorityClass and a Deployment sized to
# consume most of one worker node's allocatable memory. A later high-priority Pod
# cannot fit, so the scheduler must EVICT these to make room — which is the whole
# point of the drill. Without this, preemption never triggers and the task looks
# broken when it isn't.
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

# Pick a schedulable worker (skip control planes).
NODE="$(kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints --no-headers \
  | grep -v 'control-plane' | head -1 | awk '{print $1}')"
if [[ -z "$NODE" ]]; then
  echo "ERROR: no worker node found. Use a multi-node lab." >&2
  exit 1
fi
banner "target node: $NODE"

ALLOC="$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.memory}')"
echo "allocatable memory: $ALLOC"

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
  replicas: 6
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
            memory: "400Mi"
            cpu: "50m"
EOF

banner "waiting for filler to settle"
sleep 8
kubectl get pod -n "$NS" -o wide

cat <<EOF

Seeded.
  Namespace : $NS
  Node      : $NODE  (now largely consumed by 6 x 400Mi low-priority Pods)
  Class     : low-priority (value 1000)

The node is deliberately near-full. A high-priority Pod requesting real memory
cannot be scheduled without evicting these.

Cleanup: bash setup-preempt.sh restore
EOF
