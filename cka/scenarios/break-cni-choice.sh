#!/usr/bin/env bash
# CKA drill fault injector — CNI install, EXAM SHAPE.
# Several candidate manifests are supplied; exactly one is correct for this cluster.
# Run ON the control-plane node of a single-node kubeadm lab, as root.
#
#   bash break-cni-choice.sh           inject
#   bash break-cni-choice.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
DIR="/root/cni"
STATE="/root/.cka-cni-choice"
NETD="/etc/cni/net.d"
STASH="/root/.cka-cni-stash"
FLANNEL_URL="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the control-plane node."; exit 1; }
[ "$(id -u)" = "0" ] || { echo "run as root."; exit 1; }

if [ "$MODE" = "restore" ]; then
  [ -f "$STATE" ] || { echo "no state file — nothing to restore."; exit 1; }
  GOOD="$(sed -n 2p "$STATE")"
  echo "restoring with $GOOD ..."
  kubectl apply -f "$DIR/$GOOD" >/dev/null 2>&1
  mkdir -p "$NETD"
  systemctl restart kubelet
  echo "Applied $GOOD and restarted kubelet. Give it ~60s, then: kubectl get nodes"
  exit 0
fi

CIDR="$(grep -oP '(?<=--cluster-cidr=)[0-9./]+' /etc/kubernetes/manifests/kube-controller-manager.yaml | head -1)"
[ -n "$CIDR" ] || { echo "cannot read --cluster-cidr — is this a kubeadm control plane?"; exit 1; }

mkdir -p "$DIR" "$STASH"

echo "preparing candidate manifests ..."
curl -fsSL "$FLANNEL_URL" -o "$DIR/.base.yml" || {
  echo "cannot download the base manifest — no egress? Nothing was changed."; exit 1; }

# --- build three candidates -------------------------------------------------
# GOOD: net-conf Network matches this cluster's --cluster-cidr
sed "s#\"Network\": \"[0-9./]*\"#\"Network\": \"$CIDR\"#" "$DIR/.base.yml" > "$DIR/.good.yml"

# BAD-CIDR: applies cleanly, pods get addresses the cluster will not route
sed "s#\"Network\": \"[0-9./]*\"#\"Network\": \"172.31.0.0/16\"#" "$DIR/.base.yml" > "$DIR/.badcidr.yml"

# INCOMPLETE: DaemonSet without its ConfigMap — flannel starts with no config
awk 'BEGIN{RS="\n---\n"} !/kind: ConfigMap/ {print $0 "\n---"}' "$DIR/.base.yml" > "$DIR/.partial.yml"

# --- shuffle the letters so the mapping is not guessable ---------------------
LETTERS=(a b c)
FILES=(.good.yml .badcidr.yml .partial.yml)
IDX=($(shuf -e 0 1 2))
GOODNAME=""
for i in 0 1 2; do
  src="${FILES[${IDX[$i]}]}"
  dst="option-${LETTERS[$i]}.yaml"
  cp "$DIR/$src" "$DIR/$dst"
  [ "$src" = ".good.yml" ] && GOODNAME="$dst"
done
rm -f "$DIR"/.base.yml "$DIR"/.good.yml "$DIR"/.badcidr.yml "$DIR"/.partial.yml

# --- tear down whatever CNI is currently in place ---------------------------
if command -v helm >/dev/null && helm status cilium -n kube-system >/dev/null 2>&1; then
  helm uninstall cilium -n kube-system >/dev/null 2>&1
  sleep 5
fi
kubectl -n kube-system delete daemonset -l k8s-app=flannel >/dev/null 2>&1
kubectl delete -n kube-flannel daemonset kube-flannel-ds >/dev/null 2>&1

cp -a "$NETD"/. "$STASH"/ 2>/dev/null
rm -f "$NETD"/*.conf "$NETD"/*.conflist "$NETD"/*.json 2>/dev/null

systemctl restart kubelet

{ echo "# cka cni-choice drill"; echo "$GOODNAME"; echo "$CIDR"; } > "$STATE"
chmod 600 "$STATE"

printf 'settling'
for _ in $(seq 1 12); do printf '.'; sleep 2; done
echo
echo
echo "Three candidate CNI manifests have been placed in $DIR:"
ls -1 "$DIR"
echo
echo "The cluster has no working pod network. Exactly one of these manifests is"
echo "correct for THIS cluster. Investigate, choose, install, and prove it works."
