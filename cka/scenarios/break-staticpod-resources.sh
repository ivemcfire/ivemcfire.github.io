#!/usr/bin/env bash
# CKA drill fault injector — existing static Pod failing on its resource settings (worker node).
# Run from the bastion / control plane (needs kubectl + passwordless ssh to the worker).
#
#   bash break-staticpod-resources.sh           inject
#   bash break-staticpod-resources.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.
set -uo pipefail
MODE="${1:-break}"
NS="ops-agents"
POD="log-agent"
STATE="/tmp/.cka-staticpod-res-fault"
SSH="ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SSHIN="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion/control plane."; exit 1; }

pick_worker() {
  kubectl get nodes --no-headers --request-timeout=10s 2>/dev/null \
    | awk '$3 !~ /control-plane|master/ {print $1; exit}'
}

manifest_dir() {
  local d
  d="$($SSH "$1" "awk '/staticPodPath/ {print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null)"
  echo "${d:-/etc/kubernetes/manifests}"
}

if [ "$MODE" = "restore" ]; then
  NODE="$(sed -n 1p "$STATE" 2>/dev/null)"
  NODE="${NODE:-$(pick_worker)}"
  [ -n "$NODE" ] || { echo "no worker node found."; exit 1; }
  DIR="$(manifest_dir "$NODE")"
  $SSH "$NODE" "rm -f $DIR/$POD.yaml" 2>/dev/null
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
  rm -f "$STATE"
  echo "restored."
  exit 0
fi

NODE="$(pick_worker)"
[ -n "$NODE" ] || { echo "no worker node found."; exit 1; }
$SSH "$NODE" true 2>/dev/null || { echo "cannot ssh to $NODE without a password."; exit 1; }
DIR="$(manifest_dir "$NODE")"

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

V=$((RANDOM % 2))
if [ "$V" = "0" ]; then
  RC="50m"; RM="8Mi";  LC="200m"; LM="16Mi"
else
  RC="64";  RM="32Mi"; LC="64";   LM="128Mi"
fi

$SSHIN "$NODE" "cat > $DIR/$POD.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    app: $POD
spec:
  containers:
  - name: agent
    image: busybox:1.28
    command: ["sh", "-c", "dd if=/dev/zero of=/dev/null bs=60M count=1 2>/dev/null; echo ready; sleep 3600"]
    resources:
      requests:
        cpu: "$RC"
        memory: "$RM"
      limits:
        cpu: "$LC"
        memory: "$LM"
EOF
[ $? -eq 0 ] || { echo "failed to write the manifest on $NODE."; exit 1; }

printf '%s\n%s\n' "$NODE" "$V" > "$STATE"

echo "settling (30s)..."
sleep 30
echo "done."
