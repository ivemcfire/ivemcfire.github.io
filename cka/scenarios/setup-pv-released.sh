#!/usr/bin/env bash
# CKA drill seed — storage. DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-pv-released.sh          # seed
#         bash setup-pv-released.sh restore  # tear down
#
# Names can be overridden for an altered rep:
#   NS=analytics PV=warehouse-pv SC=warehouse-retain APP=records PATH_ON_NODE=/mnt/warehouse-data \
#     bash setup-pv-released.sh
#
# Requires: kubectl against the intended cluster/context. No ssh needed.
set -u

NS="${NS:-data-tier}"
PV="${PV:-mariadb-pv}"
SC="${SC:-mariadb-retain}"
APP="${APP:-mariadb}"
SIZE="${SIZE:-2Gi}"
PATH_ON_NODE="${PATH_ON_NODE:-/mnt/mariadb-data}"

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl delete pv "$PV" --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl patch pv "$PV" -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
  echo "restored."
  exit 0
fi

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
spec:
  capacity:
    storage: $SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $SC
  hostPath:
    path: $PATH_ON_NODE
    type: DirectoryOrCreate
EOF

# bind a claim, then delete it -- leaves the PV holding a stale reference
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $APP-old-claim
  namespace: $NS
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: $SC
  resources:
    requests:
      storage: $SIZE
  volumeName: $PV
EOF

for _ in $(seq 1 30); do
  [ "$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && break
  sleep 1
done

kubectl delete pvc "$APP-old-claim" -n "$NS" --wait=true >/dev/null 2>&1

kubectl apply -f - >/dev/null <<EOF
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
          image: mariadb:10.11
          env:
            - name: MARIADB_ROOT_PASSWORD
              value: changeme
          ports:
            - containerPort: 3306
EOF

echo "seeded. namespace: $NS"
