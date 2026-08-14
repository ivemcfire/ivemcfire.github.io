#!/usr/bin/env bash
# CKA drill seeder — a custom resource with nested spec fields, for output extraction.
# Object-only: creates one CRD + a namespace + five CRs. No node changes.
#
#   bash setup-licenses.sh           seed
#   bash setup-licenses.sh restore   remove the CRD + namespace
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-seed}"
NS=licensing

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete crd licenses.ops.example.com >/dev/null 2>&1
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  echo "Licenses CRD + namespace $NS removed on $CTX."
  exit 0
fi

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: licenses.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names:
    plural: licenses
    singular: license
    kind: License
    shortNames:
    - lic
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              tier:
                type: string
              seats:
                type: integer
              owner:
                type: object
                properties:
                  team:
                    type: string
                  contact:
                    type: string
EOF

kubectl create ns "$NS" >/dev/null 2>&1

# wait for the CRD to be established before creating CRs
for _ in $(seq 1 20); do
  kubectl get crd licenses.ops.example.com \
    -o custom-columns=E:.status.conditions[?\(@.type==\"Established\"\)].status \
    --no-headers 2>/dev/null | grep -q True && break
  sleep 1
done

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: ops.example.com/v1
kind: License
metadata:
  name: lic-analytics
  namespace: licensing
spec:
  tier: gold
  seats: 120
  owner:
    team: data-platform
    contact: dp@example.com
---
apiVersion: ops.example.com/v1
kind: License
metadata:
  name: lic-billing
  namespace: licensing
spec:
  tier: silver
  seats: 40
  owner:
    team: finance-eng
    contact: fin@example.com
---
apiVersion: ops.example.com/v1
kind: License
metadata:
  name: lic-crm
  namespace: licensing
spec:
  tier: gold
  seats: 200
  owner:
    team: sales-systems
    contact: crm@example.com
---
apiVersion: ops.example.com/v1
kind: License
metadata:
  name: lic-portal
  namespace: licensing
spec:
  tier: bronze
  seats: 15
  owner:
    team: web-frontend
    contact: web@example.com
---
apiVersion: ops.example.com/v1
kind: License
metadata:
  name: lic-warehouse
  namespace: licensing
spec:
  tier: silver
  seats: 65
  owner:
    team: logistics
    contact: wh@example.com
EOF

echo "Seeded on context: $CTX"
echo "Start here:  kubectl get licenses -n $NS"
