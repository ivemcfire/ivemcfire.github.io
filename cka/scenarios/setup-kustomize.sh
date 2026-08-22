#!/usr/bin/env bash
# CKA drill setup — Kustomize base for an overlay authoring rep.
# Creates /root/apps/base only. The overlay is the graded work.
#
#   bash setup-kustomize.sh           create the base
#   bash setup-kustomize.sh restore   remove /root/apps and the prod namespace
#
# Safe to read — this is setup, not a fault injector.

set -uo pipefail
MODE="${1:-setup}"
ROOT=/root/apps

if [ "$MODE" = "restore" ]; then
  rm -rf "$ROOT"
  kubectl delete ns prod --ignore-not-found >/dev/null 2>&1
  echo "Removed $ROOT and namespace prod."
  exit 0
fi

mkdir -p "$ROOT/base" "$ROOT/overlays/prod"

cat > "$ROOT/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gateway
  template:
    metadata:
      labels:
        app: gateway
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
YAML

cat > "$ROOT/base/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: gateway-svc
spec:
  selector:
    app: gateway
  ports:
  - port: 80
    targetPort: 80
YAML

cat > "$ROOT/base/kustomization.yaml" <<'YAML'
resources:
  - deployment.yaml
  - service.yaml
YAML

kubectl create ns prod >/dev/null 2>&1

echo "Base created at $ROOT/base:"
ls -1 "$ROOT/base"
echo "Empty overlay directory ready at $ROOT/overlays/prod"
echo "Namespace prod created."
