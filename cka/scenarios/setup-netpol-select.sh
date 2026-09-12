#!/usr/bin/env bash
# CKA drill seed — NetworkPolicy SELECTION (exam shape: candidate policies in files, pick the one that is just enough).
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-netpol-select.sh          # seed
#         bash setup-netpol-select.sh restore  # tear down
# Requires: kubectl. Writes candidate manifests to /root/netpol/.
set -u

DIR="${DIR:-/root/netpol}"

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns shop audit --ignore-not-found --wait=false >/dev/null 2>&1
  rm -rf "$DIR"
  echo "restored."
  exit 0
fi

kubectl get ns shop  >/dev/null 2>&1 || kubectl create ns shop  >/dev/null
kubectl get ns audit >/dev/null 2>&1 || kubectl create ns audit >/dev/null

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: client
          image: busybox:1.28
          command: ["sh", "-c", "sleep 3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: shop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
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
  name: backend-svc
  namespace: shop
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
  name: legacy
  namespace: shop
  labels:
    app: legacy
spec:
  containers:
    - name: client
      image: busybox:1.28
      command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: scanner
  namespace: audit
  labels:
    app: scanner
spec:
  containers:
    - name: client
      image: busybox:1.28
      command: ["sh", "-c", "sleep 3600"]
EOF

mkdir -p "$DIR"

cat > "$DIR/policy-a.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: shop
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
              kubernetes.io/metadata.name: shop
      ports:
        - protocol: TCP
          port: 80
EOF

cat > "$DIR/policy-b.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: shop
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
              kubernetes.io/metadata.name: shop
          podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 80
EOF

cat > "$DIR/policy-c.yaml" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: shop
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
              kubernetes.io/metadata.name: shop
          podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
EOF

echo "seeded. candidate policies in $DIR:"
ls -1 "$DIR"
echo
echo "CNI pods visible (policy enforcement depends on this):"
kubectl get po -A --no-headers 2>/dev/null | awk '{print $2}' | grep -Ei 'cilium|calico|canal|weave|antrea|kube-router' | head -3 || echo "  none found"
