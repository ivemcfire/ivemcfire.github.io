#!/usr/bin/env bash
# CKA drill seed — migrate an Ingress with TLS to Gateway API (exam shape).
# Needs a cluster with a Gateway API controller + GatewayClass (e.g. NGINX Gateway Fabric).
#
#   bash setup-gw-tls-migrate.sh           seed + write ~/verify-gw.sh
#   bash setup-gw-tls-migrate.sh restore   delete the namespace
#
# Env overrides for altered reps: NS= APP= HOST= SECRET= ING= GW= ROUTE= PATHP=
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-seed}"
NS="${NS:-media}"
APP="${APP:-gallery}"
HOST="${HOST:-gallery.media.local}"
SECRET="${SECRET:-media-tls}"
ING="${ING:-gallery-ing}"
GW="${GW:-gallery-gw}"
ROUTE="${ROUTE:-gallery-route}"
PATHP="${PATHP:-/photos}"

command -v kubectl >/dev/null || { echo "kubectl not found."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete ns "$NS" --wait=false >/dev/null 2>&1
  rm -f ~/verify-gw.sh
  echo "Namespace $NS deleted."
  exit 0
fi

command -v openssl >/dev/null || { echo "openssl not found."; exit 1; }
kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || { echo "Gateway API CRDs missing — wrong lab."; exit 1; }
[ -n "$(kubectl get gatewayclass --no-headers 2>/dev/null)" ] || { echo "No GatewayClass — wrong lab."; exit 1; }

kubectl create ns "$NS" >/dev/null 2>&1
kubectl -n "$NS" create deployment "$APP" --image=traefik/whoami:v1.10 --replicas=2 >/dev/null
kubectl -n "$NS" expose deployment "$APP" --name="${APP}-svc" --port=80 --target-port=80 >/dev/null

TMP="$(mktemp -d)"
openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=$HOST" \
  -keyout "$TMP/tls.key" -out "$TMP/tls.crt" >/dev/null 2>&1
kubectl -n "$NS" create secret tls "$SECRET" --cert="$TMP/tls.crt" --key="$TMP/tls.key" >/dev/null
rm -rf "$TMP"

kubectl apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $ING
  namespace: $NS
spec:
  tls:
  - hosts:
    - $HOST
    secretName: $SECRET
  rules:
  - host: $HOST
    http:
      paths:
      - path: $PATHP
        pathType: Prefix
        backend:
          service:
            name: ${APP}-svc
            port:
              number: 80
EOF

cat > ~/verify-gw.sh <<EOF
#!/usr/bin/env bash
NS=$NS; GW=$GW; ROUTE=$ROUTE; HOST=$HOST; ING=$ING; PATHP=$PATHP; APP=$APP
EOF
cat >> ~/verify-gw.sh <<'EOF'
echo "== Gateway spec"
kubectl -n $NS get gateway $GW -o jsonpath='{range .spec.listeners[*]}name={.name} port={.port} proto={.protocol} host={.hostname} mode={.tls.mode} cert={.tls.certificateRefs[*].name}{"\n"}{end}'
echo "== Gateway Programmed"
kubectl -n $NS get gateway $GW -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'
echo "== HTTPRoute spec"
kubectl -n $NS get httproute $ROUTE -o jsonpath='parent={.spec.parentRefs[*].name} section={.spec.parentRefs[*].sectionName} hosts={.spec.hostnames[*]}{"\n"}{range .spec.rules[*]}match={.matches[*].path.type}:{.matches[*].path.value} backend={.backendRefs[*].name}:{.backendRefs[*].port}{"\n"}{end}'
echo "== HTTPRoute status"
kubectl -n $NS get httproute $ROUTE -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {end}{"\n"}'
echo "== Ingress gone?"
kubectl -n $NS get ingress $ING 2>&1 | tail -1
echo "== HTTPS probe"
NP="$(kubectl -n $NS get svc -l gateway.networking.k8s.io/gateway-name=$GW -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}' 2>/dev/null)"
IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
# Prefer the Gateway data plane. A cluster may also run ingress-nginx, whose 443
# nodePort answers 404 for these hosts and reads as a broken Gateway (seen 2026-09-19).
[ -z "$NP" ] && NP="$(kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.ports[?(@.port==443)].nodePort}{"\n"}{end}' | awk 'NF==2 && !/ingress-nginx/ && /gateway|envoy|traefik/{print $2; exit}')"
if [ -z "$NP" ]; then echo "no data-plane Service with a 443 nodePort found for $GW"; exit 0; fi
curl -sk -o /dev/null -w "https $PATHP -> %{http_code}\n" --resolve "$HOST:$NP:$IP" "https://$HOST:$NP$PATHP"
curl -sk --resolve "$HOST:$NP:$IP" "https://$HOST:$NP$PATHP" | grep -m1 "^Hostname"
EOF
chmod +x ~/verify-gw.sh

kubectl -n "$NS" rollout status deploy "$APP" --timeout=90s >/dev/null 2>&1
echo "Seeded namespace $NS. Verifier: ~/verify-gw.sh"
