#!/usr/bin/env bash
# CKA drill fault injector — ingress layer (namespace `shipping`).
# Object-only faults: safe, reversible, no node changes.
# Run on a cluster that has an ingress-nginx controller.
#
#   bash break-ingress.sh           inject
#   bash break-ingress.sh restore   delete the namespace (ends the rep)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
NS="${NS:-shipping}"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  echo "Namespace $NS deleted on $CTX."
  exit 0
fi

ICLASS="$(kubectl get ingressclass --no-headers 2>/dev/null | awk 'NR==1{print $1}')"
if [ -z "$ICLASS" ]; then
  echo "WARNING: no IngressClass found on $CTX — is an ingress controller installed here?"
  ICLASS=nginx
fi

kubectl create ns "$NS" >/dev/null 2>&1

kubectl apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tracker
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tracker
  template:
    metadata:
      labels:
        app: tracker
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
  name: tracker-svc
  namespace: $NS
spec:
  selector:
    app: tracker
  ports:
  - port: 3000
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tracker-ing
  namespace: $NS
spec:
  ingressClassName: $ICLASS
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: example-service
            port:
              number: 80
EOF

echo "Fault injected on context: $CTX (namespace: $NS, ingressClass: $ICLASS)"
echo "Start here:  kubectl get ing,svc,po -n $NS"
