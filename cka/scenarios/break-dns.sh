#!/usr/bin/env bash
# CKA drill fault injector — cluster DNS (kube-system CoreDNS).
# Object-only faults: safe, reversible, no node changes.
# Random of 3 variants. Run from the bastion.
#
#   bash break-dns.sh           inject
#   bash break-dns.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
NS=mail
STATE="/tmp/.cka-dns-fault"
CMBAK="/tmp/.cka-dns-coredns-backup.yaml"
COREFILE="/tmp/.cka-dns-corefile"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

if [ "$MODE" = "restore" ]; then
  VARIANT="unknown"; REPLICAS=2
  [ -f "$STATE" ] && { VARIANT="$(sed -n 2p "$STATE")"; REPLICAS="$(sed -n 3p "$STATE")"; }

  kubectl -n kube-system scale deploy coredns --replicas="${REPLICAS:-2}" >/dev/null 2>&1
  kubectl -n kube-system patch svc kube-dns \
    -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}' >/dev/null 2>&1
  [ -f "$CMBAK" ] && kubectl replace -f "$CMBAK" >/dev/null 2>&1
  kubectl -n kube-system rollout restart deploy coredns >/dev/null 2>&1

  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  rm -f "$STATE"
  echo "Restored on $CTX (variant $VARIANT). Give CoreDNS ~30s, then re-test resolution."
  exit 0
fi

kubectl -n kube-system get deploy coredns >/dev/null 2>&1 \
  || { echo "no coredns Deployment in kube-system on $CTX — wrong cluster for this drill."; exit 1; }

REPLICAS="$(kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}' 2>/dev/null)"
[ -n "$REPLICAS" ] || REPLICAS=2

# The thing the operator is meant to test resolution from / against.
kubectl create ns "$NS" >/dev/null 2>&1
kubectl apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webmail
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webmail
  template:
    metadata:
      labels:
        app: webmail
    spec:
      containers:
      - name: web
        image: nginx:1.27
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: webmail-svc
  namespace: $NS
spec:
  selector:
    app: webmail
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: $NS
spec:
  containers:
  - name: client
    image: busybox:1.28
    command: ["sleep", "3600"]
EOF

VARIANT=$((RANDOM % 3))

case "$VARIANT" in
  0) # CoreDNS scaled to zero — no DNS server pods at all
    kubectl -n kube-system scale deploy coredns --replicas=0 >/dev/null 2>&1
    ;;
  1) # kube-dns Service selector no longer matches the CoreDNS pods — no endpoints
    kubectl -n kube-system patch svc kube-dns \
      -p '{"spec":{"selector":{"k8s-app":"kube-dns-backend"}}}' >/dev/null 2>&1
    ;;
  2) # Corefile names a cluster domain that does not exist — CoreDNS stays Running and healthy
    kubectl -n kube-system get cm coredns -o yaml > "$CMBAK" 2>/dev/null
    kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > "$COREFILE" 2>/dev/null
    sed -i 's/kubernetes cluster\.local/kubernetes cluster.invalid/' "$COREFILE"
    kubectl -n kube-system create cm coredns --from-file=Corefile="$COREFILE" \
      --dry-run=client -o yaml | kubectl -n kube-system replace -f - >/dev/null 2>&1
    kubectl -n kube-system rollout restart deploy coredns >/dev/null 2>&1
    ;;
esac

printf '%s\n%s\n%s\n' "$CTX" "$VARIANT" "$REPLICAS" > "$STATE"
echo "Fault injected on context: $CTX (namespace: $NS)"
echo "Give it ~30s, then start here:"
echo "  kubectl exec -n $NS client -- nslookup webmail-svc"
