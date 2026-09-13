#!/usr/bin/env bash
# CKA drill seed — HPA on an existing Deployment + ResourceQuota arithmetic.
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-hpa-quota.sh          # seed
#         bash setup-hpa-quota.sh restore  # tear down
#
# Names/values can be overridden for an altered rep:
#   NS=ledger APP=billing QUOTA_MI=1300 REQ_MI=700 bash setup-hpa-quota.sh
#
# Requires: kubectl. No ssh needed.
set -u

NS="${NS:-autoscale}"
APP="${APP:-api}"
QUOTA_MI="${QUOTA_MI:-1100}"
REQ_MI="${REQ_MI:-600}"

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
  echo "restored."
  exit 0
fi

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: mem-quota
  namespace: $NS
spec:
  hard:
    requests.memory: ${QUOTA_MI}Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP
  template:
    metadata:
      labels:
        app: $APP
    spec:
      containers:
      - name: $APP
        image: nginx:1.27-alpine
        resources:
          requests:
            cpu: 100m
            memory: ${REQ_MI}Mi
EOF

kubectl -n "$NS" rollout status deploy "$APP" --timeout=120s >/dev/null 2>&1
echo "seeded."
