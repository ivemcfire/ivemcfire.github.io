#!/usr/bin/env bash
# CKA drill seed — Ingress authoring, two exam-shaped tasks (ns portal + ns shop).
# Installs ingress-nginx (baremetal, NodePort) first if the cluster has no IngressClass.
#
#   bash setup-ingress-echo.sh           seed + write ~/verify-ingress.sh
#   bash setup-ingress-echo.sh restore   delete both namespaces (controller stays)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-seed}"
MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.3/deploy/static/provider/baremetal/deploy.yaml"

command -v kubectl >/dev/null || { echo "kubectl not found."; exit 1; }

if [ "$MODE" = "restore" ]; then
  kubectl delete ns portal shop --wait=false >/dev/null 2>&1
  rm -f ~/verify-ingress.sh
  echo "Namespaces portal, shop deleted."
  exit 0
fi

if [ -z "$(kubectl get ingressclass --no-headers 2>/dev/null)" ]; then
  echo "No IngressClass — installing ingress-nginx (lab prep, not part of the task)..."
  kubectl apply -f "$MANIFEST" >/dev/null || { echo "manifest apply failed."; exit 1; }
  kubectl -n ingress-nginx wait --for=condition=complete job --all --timeout=180s >/dev/null 2>&1
  kubectl -n ingress-nginx rollout status deploy ingress-nginx-controller --timeout=240s >/dev/null 2>&1 \
    || { echo "controller not ready — check: kubectl -n ingress-nginx get po"; exit 1; }
fi

mk() { # ns app svc svcport
  kubectl -n "$1" create deployment "$2" --image=traefik/whoami:v1.10 --replicas=1 >/dev/null
  kubectl -n "$1" expose deployment "$2" --name="$3" --port="$4" --target-port=80 >/dev/null
}
kubectl create ns portal >/dev/null 2>&1
kubectl create ns shop >/dev/null 2>&1
mk portal echo echo-svc 8080
mk shop cart cart-svc 80
mk shop catalog catalog-svc 9090

cat > ~/verify-ingress.sh <<'EOF'
#!/usr/bin/env bash
# usage: bash ~/verify-ingress.sh a   |   bash ~/verify-ingress.sh b
IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
NP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)"
spec() { kubectl -n "$1" get ingress "$2" -o jsonpath='class={.spec.ingressClassName}{"\n"}{range .spec.rules[*]}host={.host}{"\n"}{range .http.paths[*]}  path={.path} type={.pathType} -> {.backend.service.name}:{.backend.service.port.number}{.backend.service.port.name}{"\n"}{end}{end}'; }
probe() { # host path
  code="$(curl -s -o /tmp/.ing-body -w '%{http_code}' --resolve "$1:$NP:$IP" "http://$1:$NP$2")"
  echo "http://$1$2 -> $code $(grep -m1 ^Hostname /tmp/.ing-body)"
}
case "${1:-}" in
  a) echo "== spec"; spec portal echo-ing
     echo "== probes"; probe example.com /echo; probe other.com /echo ;;
  b) echo "== spec"; spec shop shop-ing
     echo "== probes"; probe shop.example.com /cart; probe shop.example.com /cart/items
     probe shop.example.com /catalog; probe shop.example.com /catalog/books ;;
  *) echo "usage: bash ~/verify-ingress.sh a|b" ;;
esac
EOF
chmod +x ~/verify-ingress.sh

kubectl -n portal rollout status deploy echo --timeout=90s >/dev/null 2>&1
kubectl -n shop rollout status deploy cart --timeout=90s >/dev/null 2>&1
kubectl -n shop rollout status deploy catalog --timeout=90s >/dev/null 2>&1
echo "Seeded portal + shop. Verifier: ~/verify-ingress.sh a|b"
