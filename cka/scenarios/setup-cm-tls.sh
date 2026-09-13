#!/usr/bin/env bash
# CKA drill seed — edit an existing ConfigMap (nginx TLS protocols) and make the change take effect.
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Usage:  bash setup-cm-tls.sh          # seed
#         bash setup-cm-tls.sh restore  # tear down
# Requires: kubectl, openssl. Leaves /root/verify-tls.sh (the supplied verification).
set -u

NS="${NS:-secure-web}"
APP="${APP:-web-tls}"
CM="${CM:-nginx-tls-config}"

if [ "${1:-}" = "restore" ]; then
  kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null 2>&1
  rm -f /root/verify-tls.sh
  echo "restored."
  exit 0
fi

command -v openssl >/dev/null || { echo "GATE: openssl not found."; exit 1; }

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS" >/dev/null

T="$(mktemp -d)"
openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=$APP.$NS" \
  -keyout "$T/tls.key" -out "$T/tls.crt" >/dev/null 2>&1
kubectl -n "$NS" create secret tls "$APP-cert" --cert="$T/tls.crt" --key="$T/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
rm -rf "$T"

kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CM
  namespace: $NS
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name $APP.$NS;
        ssl_certificate     /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.3;
        location / {
            return 200 "secure-web ok\n";
        }
    }
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
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 443
        volumeMounts:
        - name: conf
          mountPath: /etc/nginx/conf.d
        - name: tls
          mountPath: /etc/nginx/tls
          readOnly: true
      volumes:
      - name: conf
        configMap:
          name: $CM
      - name: tls
        secret:
          secretName: $APP-cert
---
apiVersion: v1
kind: Service
metadata:
  name: $APP
  namespace: $NS
spec:
  selector:
    app: $APP
  ports:
  - port: 443
    targetPort: 443
EOF

cat > /root/verify-tls.sh <<EOF
#!/usr/bin/env bash
# Verification supplied with the task.
probe() {
  kubectl -n $NS run tls-probe-\$RANDOM --image=curlimages/curl:8.10.1 --rm -i --restart=Never --quiet -- \\
    curl -sk -m 5 "\$@" https://$APP.$NS 2>/dev/null
}
if probe --tlsv1.2 --tls-max 1.2 | grep -q 'secure-web ok'; then echo "PASS  TLSv1.2 accepted"; else echo "FAIL  TLSv1.2 accepted"; fi
if probe --tlsv1.3 | grep -q 'secure-web ok'; then echo "PASS  TLSv1.3 accepted"; else echo "FAIL  TLSv1.3 accepted"; fi
EOF
chmod 755 /root/verify-tls.sh

kubectl -n "$NS" rollout status deploy "$APP" --timeout=120s >/dev/null 2>&1
echo "seeded."
