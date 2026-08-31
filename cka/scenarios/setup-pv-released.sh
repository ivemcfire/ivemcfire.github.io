#!/usr/bin/env bash
# CKA drill seed — storage. DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-pv-released.sh          # seed
#         bash setup-pv-released.sh restore  # tear down
# Requires: kubectl against the intended cluster/context. No ssh needed.
set -u

NS=data-tier
PV=mariadb-pv

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl delete pv "$PV" --ignore-not-found --wait=false >/dev/null 2>&1
  kubectl patch pv "$PV" -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1
  echo "restored."
  exit 0
fi

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: mariadb-retain
  hostPath:
    path: /mnt/mariadb-data
    type: DirectoryOrCreate
EOF

# bind a claim, then delete it -- leaves the PV holding a stale reference
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-old-claim
  namespace: data-tier
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: mariadb-retain
  resources:
    requests:
      storage: 2Gi
  volumeName: mariadb-pv
EOF

for _ in $(seq 1 30); do
  [ "$(kubectl get pv "$PV" -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] && break
  sleep 1
done

kubectl delete pvc mariadb-old-claim -n "$NS" --wait=true >/dev/null 2>&1

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: data-tier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
        - name: mariadb
          image: mariadb:10.11
          env:
            - name: MARIADB_ROOT_PASSWORD
              value: changeme
          ports:
            - containerPort: 3306
EOF

echo "seeded. namespace: $NS"
