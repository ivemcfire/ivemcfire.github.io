#!/usr/bin/env bash
# CKA drill fault injector — apiserver's etcd connection (control plane).
#
#   bash break-etcd-certs.sh           inject (one of three variants, at random)
#   bash break-etcd-certs.sh 0|1|2     inject a specific variant
#   bash break-etcd-certs.sh restore   undo it
#
# ONE fault per run. All three break the apiserver's connection to etcd, so the
# symptom is identical every time: kubectl dies with connection refused on 6443,
# and kube-apiserver crashloops. The diagnosis is which flag is wrong.
#
# Restore does NOT need kubectl (the API is down while the fault is live) —
# the control-plane host is recorded at break time.
#
# Do not read this file before attempting the drill.

set -uo pipefail

STATE="/tmp/.cka-etcd-fault"
STASH="/root/.cka-fault"
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"

MODE="${1:-break}"

if [ "$MODE" = "restore" ]; then
  if [ -f "$STATE" ]; then
    CP="$(sed -n 1p "$STATE")"; VARIANT="$(sed -n 2p "$STATE")"
  else
    CP="$(kubectl config current-context 2>/dev/null)-controlplane"; VARIANT="unknown"
  fi
  [ -n "$CP" ] || { echo "cannot determine the control-plane host."; exit 1; }
  $SSH "$CP" "[ -f $STASH/kube-apiserver.yaml ] && cp -f $STASH/kube-apiserver.yaml $MANIFEST" >/dev/null 2>&1
  rm -f "$STATE"
  echo "Restored on $CP (variant $VARIANT). The apiserver needs ~60s — then: kubectl get nodes"
  exit 0
fi

CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context."; exit 1; }

CP="$(kubectl get nodes --no-headers -o custom-columns=N:.metadata.name,R:.metadata.labels 2>/dev/null \
      | awk '/control-plane|master/ {print $1; exit}')"
[ -n "$CP" ] || CP="${CTX}-controlplane"

case "$MODE" in
  0|1|2) VARIANT="$MODE" ;;
  *)     VARIANT=$((RANDOM % 3)) ;;
esac

$SSH "$CP" "mkdir -p $STASH && cp -n $MANIFEST $STASH/kube-apiserver.yaml" \
  || { echo "ssh to $CP failed — is this the right cluster?"; exit 1; }

case "$VARIANT" in
  0) # plaintext scheme against a TLS listener
     $SSH "$CP" "sed -i 's|--etcd-servers=https://|--etcd-servers=http://|' $MANIFEST" >/dev/null 2>&1 ;;
  1) # the cluster CA instead of the etcd CA — cert chain will not verify
     $SSH "$CP" "sed -i 's|--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt|--etcd-cafile=/etc/kubernetes/pki/ca.crt|' $MANIFEST" >/dev/null 2>&1 ;;
  2) # client cert path that does not exist
     $SSH "$CP" "sed -i 's|--etcd-certfile=.*|--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client-old.crt|' $MANIFEST" >/dev/null 2>&1 ;;
esac

printf '%s\n%s\n' "$CP" "$VARIANT" > "$STATE"
echo "Fault injected on $CP (context: $CTX)."
echo "Give the kubelet ~30s, then start here:  kubectl get nodes"
