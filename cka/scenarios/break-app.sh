#!/usr/bin/env bash
# CKA drill fault injector — application layer (namespace `storefront`).
# Object-only faults: safe, reversible, no node changes.
#
#   bash break-app.sh           inject
#   bash break-app.sh restore   delete the namespace (ends the rep)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
NS=storefront

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  echo "Namespace $NS deleted on $CTX."
  exit 0
fi

kubectl create ns "$NS" >/dev/null 2>&1

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: storefront
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
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
  name: catalog-svc
  namespace: storefront
spec:
  selector:
    app: catalog-web
  ports:
  - port: 8080
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: pricing
  namespace: storefront
spec:
  containers:
  - name: pricing
    image: nginx:1.27
    envFrom:
    - configMapRef:
        name: pricing-config
EOF

echo "Fault injected on context: $CTX (namespace: $NS)"
echo "Start here:  kubectl get all -n $NS"
