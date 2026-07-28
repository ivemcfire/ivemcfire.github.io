#!/usr/bin/env bash
# CKA drill fault injector — kubelet layer (worker node).
# Run from the bastion/student-node (needs kubectl + passwordless ssh to nodes).
#
#   bash break-kubelet.sh           inject (one of three variants, chosen at random)
#   bash break-kubelet.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
STATE="/tmp/.cka-kubelet-fault"
STASH="/root/.cka-fault"
KCONF="/etc/kubernetes/kubelet.conf"
KCFG="/var/lib/kubelet/config.yaml"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

pick_worker() {
  kubectl get nodes --no-headers 2>/dev/null \
    | awk '$3 !~ /control-plane|master/ {print $1; exit}'
}

SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"

if [ "$MODE" = "restore" ]; then
  if [ -f "$STATE" ]; then
    NODE="$(sed -n 2p "$STATE")"; VARIANT="$(sed -n 3p "$STATE")"
  else
    NODE="$(pick_worker)"; VARIANT="unknown"
  fi
  [ -n "$NODE" ] || { echo "cannot determine the affected node."; exit 1; }

  $SSH "$NODE" "
    [ -f $STASH/kubelet.conf ]  && cp -f $STASH/kubelet.conf  $KCONF
    [ -f $STASH/config.yaml ]   && cp -f $STASH/config.yaml   $KCFG
    systemctl enable kubelet >/dev/null 2>&1
    systemctl restart kubelet
  " >/dev/null 2>&1
  rm -f "$STATE"
  echo "Restored on $NODE (variant $VARIANT). Give it ~30s, then: kubectl get nodes"
  exit 0
fi

NODE="$(pick_worker)"
[ -n "$NODE" ] || { echo "no worker node found in context $CTX."; exit 1; }

VARIANT=$((RANDOM % 3))

# Pristine copies first — this is what `restore` puts back.
$SSH "$NODE" "mkdir -p $STASH && cp -n $KCONF $STASH/kubelet.conf; cp -n $KCFG $STASH/config.yaml" \
  || { echo "ssh to $NODE failed — is this the right cluster?"; exit 1; }

case "$VARIANT" in
  0) # service stopped and disabled — survives a node reboot
    $SSH "$NODE" "systemctl disable --now kubelet" >/dev/null 2>&1 ;;
  1) # kubelet runs but talks to the wrong API server port
    $SSH "$NODE" "sed -i '/server:/s/:6443/:6553/' $KCONF; systemctl restart kubelet" >/dev/null 2>&1 ;;
  2) # kubelet config carries an invalid value — the service fails to come up
    $SSH "$NODE" "sed -i 's|^cgroupDriver:.*|cgroupDriver: cgroupfsX|' $KCFG; grep -q '^cgroupDriver:' $KCFG || echo 'cgroupDriver: cgroupfsX' >> $KCFG; systemctl restart kubelet" >/dev/null 2>&1 ;;
esac

printf '%s\n%s\n%s\n' "$CTX" "$NODE" "$VARIANT" > "$STATE"
echo "Fault injected on context: $CTX"
echo "Start here:  kubectl get nodes"
