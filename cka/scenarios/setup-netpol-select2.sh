#!/usr/bin/env bash
# CKA drill seed — NetworkPolicy SELECTION, exam shape #2 (namespace / namespace+pod / namespace+pod+CIDR).
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-netpol-select2.sh          # seed
#         bash setup-netpol-select2.sh restore  # tear down
# Requires: kubectl. Writes candidate manifests to /root/netpol/ (file numbers shuffled each run).
set -u

DIR="${DIR:-/root/netpol}"

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns payments monitoring --ignore-not-found --wait=false >/dev/null 2>&1
  rm -rf "$DIR"
  echo "restored."
  exit 0
fi

kubectl get ns payments   >/dev/null 2>&1 || kubectl create ns payments   >/dev/null
kubectl get ns monitoring >/dev/null 2>&1 || kubectl create ns monitoring >/dev/null

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: payments
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
        - name: client
          image: busybox:1.36
          command: ["sh", "-c", "sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: payments
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: api
    spec:
      containers:
        - name: api
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: payments
spec:
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: batch
  namespace: payments
  labels:
    app: batch
    tier: web
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: prober
  namespace: monitoring
  labels:
    app: frontend
spec:
  containers:
    - name: client
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
EOF

mkdir -p "$DIR"
rm -f "$DIR"/*.yaml

TMP="$(mktemp -d)"

cat > "$TMP/ns-only" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: payments
EOF

cat > "$TMP/ns-pod" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: payments
          podSelector:
            matchLabels:
              app: frontend
EOF

cat > "$TMP/ns-pod-cidr" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: payments
          podSelector:
            matchLabels:
              app: frontend
        - ipBlock:
            cidr: 10.200.0.0/16
EOF

n=1
for f in $(printf '%s\n' ns-only ns-pod ns-pod-cidr | shuf); do
  cp "$TMP/$f" "$DIR/netpol$n.yaml"
  n=$((n + 1))
done
rm -rf "$TMP"

kubectl -n payments rollout status deploy frontend --timeout=120s >/dev/null 2>&1
kubectl -n payments rollout status deploy backend  --timeout=120s >/dev/null 2>&1
kubectl -n payments wait --for=condition=Ready pod/batch --timeout=120s >/dev/null 2>&1
kubectl -n monitoring wait --for=condition=Ready pod/prober --timeout=120s >/dev/null 2>&1

echo "seeded. candidate policies in $DIR:"
ls -1 "$DIR"
echo
echo "CNI pods visible (policy enforcement depends on this):"
kubectl get po -A --no-headers 2>/dev/null | awk '{print $2}' | grep -Ei 'cilium|calico|canal|weave|antrea|kube-router' | head -3 || echo "  none found"
