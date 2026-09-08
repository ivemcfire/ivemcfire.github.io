#!/usr/bin/env bash
# CKA drill fault injector — static pod layer (control plane).
# Run from the bastion/student-node (needs kubectl + passwordless ssh to the control plane).
#
#   bash break-staticpod.sh           inject (random component, random variant)
#   bash break-staticpod.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
STATE="/tmp/.cka-staticpod-fault"
STASH="/root/.cka-fault"
NS="apps"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

pick_cp() {
  kubectl get nodes --no-headers 2>/dev/null \
    | awk '$3 ~ /control-plane|master/ {print $1; exit}'
}

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [ "$MODE" = "restore" ]; then
  if [ -f "$STATE" ]; then
    NODE="$(sed -n 2p "$STATE")"; VARIANT="$(sed -n 3p "$STATE")"; COMP="$(sed -n 4p "$STATE")"
  else
    NODE="$(pick_cp)"; VARIANT="unknown"; COMP=""
  fi
  [ -n "$NODE" ] || { echo "cannot determine the control-plane node."; exit 1; }

  $SSH "$NODE" "
    for c in kube-scheduler kube-controller-manager; do
      [ -f $STASH/\$c.yaml ] && cp -f $STASH/\$c.yaml /etc/kubernetes/manifests/\$c.yaml
    done
    systemctl restart kubelet" >/dev/null 2>&1
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  rm -f "$STATE"
  echo "Restored on $NODE (${COMP:-component unknown}, variant $VARIANT). Give it ~40s, then: kubectl get po -n kube-system"
  exit 0
fi

NODE="$(pick_cp)"
[ -n "$NODE" ] || { echo "no control-plane node found in context $CTX."; exit 1; }

COMPS=(kube-scheduler kube-controller-manager)
COMP="${COMPS[$((RANDOM % 2))]}"
MANIFEST="/etc/kubernetes/manifests/$COMP.yaml"
VARIANT=$((RANDOM % 2))

# Always keep a pristine copy first — this is what `restore` puts back.
$SSH "$NODE" "mkdir -p $STASH && cp -n $MANIFEST $STASH/$COMP.yaml" \
  || { echo "ssh to $NODE failed — is this the right cluster?"; exit 1; }

case "$VARIANT" in
  0) # manifest removed from the static pod directory
    $SSH "$NODE" "mv -f $MANIFEST $STASH/removed-$COMP.yaml" ;;
  1) # manifest present but pointing at an image tag that does not exist
    $SSH "$NODE" "sed -i 's|image: \(.*\)$COMP:.*|image: \1$COMP:v9.99.9|' $MANIFEST" ;;
esac

# Give the operator a visible symptom to chase.
kubectl create ns "$NS" >/dev/null 2>&1
sleep 25   # let the kubelet re-sync the manifest first, or the pods win the race and schedule
kubectl create deployment frontend --image=nginx:1.27 --replicas=3 -n "$NS" >/dev/null 2>&1

printf '%s\n%s\n%s\n%s\n' "$CTX" "$NODE" "$VARIANT" "$COMP" > "$STATE"
echo "Fault injected on context: $CTX"
echo "Start here:  kubectl get deploy,po -n $NS"
