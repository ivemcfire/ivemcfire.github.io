#!/usr/bin/env bash
# CKA drill fault injector — kubelet client certificate, dangling symlink (worker node).
# Run from the bastion/student-node (needs kubectl + passwordless ssh to nodes).
#
#   bash break-kubelet-pem.sh           inject
#   bash break-kubelet-pem.sh restore   undo it (safety net — use only if stuck)
#
# Do not read this file before attempting the drill.

set -uo pipefail

MODE="${1:-break}"
STATE="/tmp/.cka-kubelet-pem-fault"
STASH="/root/.cka-pem-fault"
PKI="/var/lib/kubelet/pki"
CUR="$PKI/kubelet-client-current.pem"
BOOT="/etc/kubernetes/bootstrap-kubelet.conf"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the bastion."; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null)"
[ -n "$CTX" ] || { echo "no kubectl context — check your kubeconfig."; exit 1; }

SSH="ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

pick_worker() {
  kubectl get nodes --no-headers --request-timeout=10s 2>/dev/null \
    | awk '$3 !~ /control-plane|master/ {print $1; exit}'
}

quiet() { grep -viE '^warning: permanently added|^$' || true; }

if [ "$MODE" = "restore" ]; then
  NODE="$([ -f "$STATE" ] && sed -n 2p "$STATE" || pick_worker)"
  [ -n "$NODE" ] || { echo "cannot determine the affected node."; exit 1; }

  $SSH "$NODE" "
    if [ -f $STASH/link_target ]; then
      rm -f $CUR
      ln -sf \$(cat $STASH/link_target) $CUR
    elif [ -f $STASH/kubelet-client-current.pem ]; then
      rm -f $CUR
      cp -f $STASH/kubelet-client-current.pem $CUR
      chmod 600 $CUR
    fi
    [ -f ${BOOT}.disabled ] && mv ${BOOT}.disabled $BOOT
    systemctl restart --no-block kubelet
  " 2>&1 | quiet
  rm -f "$STATE"
  echo "Restored on $NODE. Give it ~40s, then: kubectl get nodes"
  exit 0
fi

echo "context: $CTX"
NODE="$(pick_worker)"
[ -n "$NODE" ] || { echo "no worker node found in context $CTX — is this a kubeadm cluster?"; exit 1; }
echo "target:  $NODE"

$SSH "$NODE" "mkdir -p $STASH" 2>&1 | quiet
$SSH "$NODE" "test -d $PKI" || {
  echo "cannot reach $NODE over ssh, or $PKI is missing. Nothing was changed."
  exit 1
}

$SSH "$NODE" "
  set -e
  cd $PKI

  if [ -L $CUR ]; then
    readlink -f $CUR > $STASH/link_target
  else
    cp -n $CUR $STASH/kubelet-client-current.pem
  fi

  # Ensure a REAL, valid dated certificate exists. This is the file the drill
  # must find and re-point at — the fault never touches it.
  DATED=\$(ls -1 kubelet-client-????-??-??-*.pem 2>/dev/null | tail -1)
  if [ -z \"\$DATED\" ]; then
    DATED=\"kubelet-client-\$(date -d '-32 days' +%Y-%m-%d-%H-%M-%S).pem\"
    cp \$(readlink -f $CUR) \$DATED
    chmod 600 \$DATED
  fi

  # THE FAULT: current.pem becomes a symlink to a target that does not exist.
  rm -f $CUR
  ln -s $PKI/kubelet-client-rotated.pem $CUR

  if [ -f $BOOT ]; then mv $BOOT ${BOOT}.disabled; fi

  systemctl restart --no-block kubelet
" 2>&1 | quiet

if ! $SSH "$NODE" "test -L $CUR && ! test -e $CUR"; then
  echo "injection did not take on $NODE. Check: ssh $NODE 'ls -l $PKI'"
  exit 1
fi

{ echo "# cka kubelet-pem fault"; echo "$NODE"; echo "$CTX"; } > "$STATE"

printf 'settling'
for _ in $(seq 1 10); do printf '.'; sleep 2; done
echo
echo "Environment prepared on context $CTX."
echo "Something is wrong with the cluster. Investigate and fix it."
