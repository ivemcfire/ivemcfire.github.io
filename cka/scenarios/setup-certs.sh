#!/usr/bin/env bash
# setup-certs.sh — seeds the "certificate" extraction scenario (CKA retake prep, 2026-08-14).
#
# SAFE TO READ. This is a SEEDER, not a fault injection — there is no hidden break.
# It creates a namespace with Pods whose names contain "certificate", plus a
# Certificate CRD and several custom resources carrying NESTED spec fields.
#
# Usage:
#   bash setup-certs.sh            # create everything
#   bash setup-certs.sh restore    # remove everything it created
#
# Requires: kubectl against the intended cluster. Creates nothing outside ns "pki".

set -euo pipefail

NS="${NS:-pki}"

banner() { printf '\n== %s ==\n' "$1"; }

if [[ "${1:-}" == "restore" ]]; then
  banner "removing scenario"
  kubectl delete ns "$NS" --ignore-not-found --wait=false
  kubectl delete crd certificates.pki.example.com --ignore-not-found
  echo "done."
  exit 0
fi

banner "context check"
kubectl config current-context || true
kubectl get nodes -o name

banner "namespace $NS"
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -

banner "pods"
for p in certificate-api certificate-worker certificate-db certificate-cache certificate-audit; do
  kubectl run "$p" -n "$NS" --image=nginx:1.27 \
    --labels="tier=pki,app.kubernetes.io/name=${p#certificate-}" \
    --dry-run=client -o yaml | kubectl apply -f -
done

# A couple of decoys that must NOT match a name-based filter.
for p in vault-agent secrets-sync; do
  kubectl run "$p" -n "$NS" --image=nginx:1.27 \
    --labels="tier=pki,app.kubernetes.io/name=$p" \
    --dry-run=client -o yaml | kubectl apply -f -
done

banner "Certificate CRD"
cat <<'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: certificates.pki.example.com
spec:
  group: pki.example.com
  scope: Namespaced
  names:
    plural: certificates
    singular: certificate
    kind: Certificate
    shortNames:
    - cert
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
              issuer:
                type: string
              details:
                type: object
                properties:
                  appName:
                    type: string
                  commonName:
                    type: string
                  expiryDays:
                    type: integer
EOF

banner "waiting for CRD to register"
kubectl wait --for=condition=Established crd/certificates.pki.example.com --timeout=60s

banner "custom resources"
create_cert() {
  cat <<EOF | kubectl apply -f -
apiVersion: pki.example.com/v1
kind: Certificate
metadata:
  name: $1
  namespace: $NS
spec:
  issuer: $2
  details:
    appName: $3
    commonName: $4
    expiryDays: $5
EOF
}

create_cert cert-frontend  letsencrypt  storefront  www.example.com      90
create_cert cert-api       internal-ca  api-server  api.example.com      365
create_cert cert-metrics   internal-ca  prometheus  metrics.example.com  180
create_cert cert-legacy    selfsigned   billing     billing.example.com  30

banner "seeded"
kubectl get pod -n "$NS"
kubectl get certificates -n "$NS"
echo
echo "Namespace: $NS"
echo "Cleanup:   bash setup-certs.sh restore"
