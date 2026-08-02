#!/usr/bin/env bash
# CKA drill fault injector — ResourceQuota vs Deployment (namespace `analytics`).
# Object-only faults: safe, reversible, no node changes.
#
#   bash break-quota.sh           inject
#   bash break-quota.sh restore   delete the namespace (ends the rep)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
NS=analytics

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  echo "Namespace $NS deleted on $CTX."
  exit 0
fi

kubectl create ns "$NS" >/dev/null 2>&1

kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: analytics-quota
  namespace: $NS
spec:
  hard:
    requests.cpu: "300m"
    requests.memory: 300Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporter
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: reporter
  template:
    metadata:
      labels:
        app: reporter
    spec:
      containers:
      - name: web
        image: nginx:1.27
        resources:
          requests:
            cpu: "150m"
            memory: 150Mi
          limits:
            cpu: "300m"
            memory: 300Mi
EOF

echo "Fault injected on context: $CTX (namespace: $NS)"
echo "Start here:  kubectl get deploy,rs,po -n $NS"
