#!/usr/bin/env bash
# CKA drill fault injector — CNI layer.
# Run from the bastion/student-node (needs kubectl + passwordless ssh to nodes).
#
#   bash break-cni.sh           inject the fault
#   bash break-cni.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
STATE="/tmp/.cka-cni-fault"
STASH="/root/.cka-fault"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }

CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

pick_worker() {
  kubectl get nodes --no-headers 2>/dev/null \
    | awk '$3 !~ /control-plane|master/ {print $1; exit}'
}

case "$MODE" in
  break)
    NODE="$(pick_worker)"
    [ -n "$NODE" ] || { echo "no worker node found in context $CTX."; exit 1; }

    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NODE" \
      "mkdir -p $STASH && mv /etc/cni/net.d/*.conflist $STASH/ 2>/dev/null; systemctl restart kubelet" \
      || { echo "ssh to $NODE failed — is this the right cluster?"; exit 1; }

    printf '%s\n%s\n' "$CTX" "$NODE" > "$STATE"
    echo "Fault injected on context: $CTX"
    echo "Start here:  kubectl get nodes"
    ;;

  restore)
    if [ -f "$STATE" ]; then
      NODE="$(sed -n 2p "$STATE")"
    else
      NODE="$(pick_worker)"
    fi
    [ -n "$NODE" ] || { echo "cannot determine the affected node."; exit 1; }

    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NODE" \
      "mv $STASH/*.conflist /etc/cni/net.d/ 2>/dev/null; systemctl restart kubelet"
    rm -f "$STATE"
    echo "Restored on $NODE. Give it ~30s, then: kubectl get nodes"
    ;;

  *)
    echo "usage: bash break-cni.sh [break|restore]"; exit 1 ;;
esac
