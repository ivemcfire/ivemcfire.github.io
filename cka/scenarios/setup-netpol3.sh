#!/usr/bin/env bash
# setup-netpol3.sh — seeds a THREE-POLICY NetworkPolicy triage scenario.
# CKA retake prep 2026-08-14 — exam Q10 shape (investigate netpol1/2/3, modify the blocker).
#
# SAFE TO READ ONLY AFTER THE DRILL. It names which policy is the blocker.
#
# Requires a cluster with an ENFORCING CNI (KodeKloud "CKA Mock Exam 2" = Calico).
# On flannel/bare k3s every probe passes and the drill is meaningless.
#
# Usage:
#   bash setup-netpol3.sh            # create everything
#   bash setup-netpol3.sh restore    # remove everything it created
#
# Creates nothing outside namespace "ecom".

set -euo pipefail

NS="${NS:-ecom}"

if [[ "${1:-}" == "restore" ]]; then
  kubectl delete ns "$NS" --ignore-not-found --wait=false
  echo "removed namespace $NS."
  exit 0
fi

kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl apply -f - >/dev/null <<'EOF'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: ecom
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
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: ecom
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ecom
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: shell
        image: busybox:1.28
        command: ["sleep", "3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db
  namespace: ecom
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: web
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: ecom
spec:
  selector:
    app: db
  ports:
  - port: 80
    targetPort: 80
---
# netpol1 — DISTRACTOR: locks down db ingress entirely. Nothing to do with frontend->backend.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netpol1
  namespace: ecom
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
---
# netpol2 — THE BLOCKER: selects backend, admits only app=monitoring. frontend is not admitted.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netpol2
  namespace: ecom
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: monitoring
    ports:
    - protocol: TCP
      port: 80
---
# netpol3 — DISTRACTOR: db egress to DNS only. Does not select frontend or backend.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: netpol3
  namespace: ecom
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
EOF

kubectl -n "$NS" rollout status deploy/backend --timeout=90s >/dev/null 2>&1 || true
kubectl -n "$NS" rollout status deploy/frontend --timeout=90s >/dev/null 2>&1 || true

echo "Scenario ready in namespace $NS."
echo "Start here:  kubectl get netpol -n $NS"
