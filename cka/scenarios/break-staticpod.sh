#!/usr/bin/env bash
# CKA drill fault injector — static pod layer (control plane).
# Run from the bastion/student-node (needs kubectl + passwordless ssh to the control plane).
#
#   bash break-staticpod.sh           inject (one of two variants, chosen at random)
#   bash break-staticpod.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
STATE="/tmp/.cka-staticpod-fault"
STASH="/root/.cka-fault"
MANIFEST="/etc/kubernetes/manifests/kube-scheduler.yaml"
NS="apps"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

pick_cp() {
  kubectl get nodes --no-headers 2>/dev/null \
    | awk '$3 ~ /control-plane|master/ {print $1; exit}'
}

if [ "$MODE" = "restore" ]; then
  if [ -f "$STATE" ]; then
    NODE="$(sed -n 2p "$STATE")"; VARIANT="$(sed -n 3p "$STATE")"
  else
    NODE="$(pick_cp)"; VARIANT="unknown"
  fi
  [ -n "$NODE" ] || { echo "cannot determine the control-plane node."; exit 1; }

  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NODE" \
    "[ -f $STASH/kube-scheduler.yaml ] && cp -f $STASH/kube-scheduler.yaml $MANIFEST; systemctl restart kubelet" \
    >/dev/null 2>&1
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  rm -f "$STATE"
  echo "Restored on $NODE (variant $VARIANT). Give it ~40s, then: kubectl get po -n kube-system"
  exit 0
fi

NODE="$(pick_cp)"
[ -n "$NODE" ] || { echo "no control-plane node found in context $CTX."; exit 1; }

VARIANT=$((RANDOM % 2))

# Always keep a pristine copy first — this is what `restore` puts back.
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NODE" \
  "mkdir -p $STASH && cp -n $MANIFEST $STASH/kube-scheduler.yaml" \
  || { echo "ssh to $NODE failed — is this the right cluster?"; exit 1; }

case "$VARIANT" in
  0) # manifest removed from the static pod directory
    ssh -o StrictHostKeyChecking=no "$NODE" "mv -f $MANIFEST $STASH/removed-kube-scheduler.yaml" ;;
  1) # manifest present but pointing at an image tag that does not exist
    ssh -o StrictHostKeyChecking=no "$NODE" \
      "sed -i 's|image: \(.*\)kube-scheduler:.*|image: \1kube-scheduler:v9.99.9|' $MANIFEST" ;;
esac

# Give the operator a visible symptom to chase.
kubectl create ns "$NS" >/dev/null 2>&1
kubectl create deployment frontend --image=nginx:1.27 --replicas=3 -n "$NS" >/dev/null 2>&1

printf '%s\n%s\n%s\n' "$CTX" "$NODE" "$VARIANT" > "$STATE"
echo "Fault injected on context: $CTX"
echo "Start here:  kubectl get po -n $NS"
