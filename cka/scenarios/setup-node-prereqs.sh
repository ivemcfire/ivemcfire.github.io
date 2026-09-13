#!/usr/bin/env bash
# CKA drill seed — node prerequisites: install a .deb, enable its service, kernel modules + sysctls (worker node).
# DO NOT READ THIS FILE BEFORE ATTEMPTING THE DRILL.
# Run from the control plane / bastion (needs kubectl + passwordless ssh to the worker).
#
#   bash setup-node-prereqs.sh           seed
#   bash setup-node-prereqs.sh restore   undo (removes the package, restores stashed config)
#
# Leaves /root/cka-shim_1.0_all.deb and /root/verify-prereqs.sh on the worker.
set -uo pipefail

MODE="${1:-seed}"
STATE="/tmp/.cka-node-prereqs"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

command -v kubectl >/dev/null || { echo "kubectl not found — run this on the control plane."; exit 1; }

pick_worker() {
  kubectl get nodes --no-headers --request-timeout=10s 2>/dev/null \
    | awk '$3 !~ /control-plane|master/ {print $1; exit}'
}

if [ "$MODE" = "restore" ]; then
  NODE="$([ -f "$STATE" ] && cat "$STATE" || pick_worker)"
  [ -n "$NODE" ] || { echo "cannot determine the worker node."; exit 1; }
  $SSH "$NODE" bash -s <<'REMOTE' 2>/dev/null
STASH=/root/.cka-prereqs-stash
systemctl disable --now cka-shim >/dev/null 2>&1
dpkg --purge cka-shim >/dev/null 2>&1
rm -f /root/cka-shim_1.0_all.deb /root/verify-prereqs.sh
if [ -d "$STASH" ]; then
  for f in "$STASH"/sysctl.d/* ; do [ -e "$f" ] && mv -f "$f" /etc/sysctl.d/ ; done
  for f in "$STASH"/modules-load.d/* ; do [ -e "$f" ] && mv -f "$f" /etc/modules-load.d/ ; done
  [ -f "$STASH/sysctl.conf" ] && cp -f "$STASH/sysctl.conf" /etc/sysctl.conf
  rm -rf "$STASH"
fi
modprobe overlay >/dev/null 2>&1
modprobe br_netfilter >/dev/null 2>&1
sysctl --system >/dev/null 2>&1
REMOTE
  rm -f "$STATE"
  echo "restored on $NODE."
  exit 0
fi

NODE="$(pick_worker)"
[ -n "$NODE" ] || { echo "no worker node found."; exit 1; }
$SSH "$NODE" 'command -v dpkg-deb >/dev/null && command -v systemctl >/dev/null' || {
  echo "GATE: $NODE is not reachable over ssh, or has no dpkg/systemd. Nothing was changed."
  exit 1
}
echo "$NODE" > "$STATE"

$SSH "$NODE" bash -s <<'REMOTE' 2>/dev/null
set -u
STASH=/root/.cka-prereqs-stash
mkdir -p "$STASH/sysctl.d" "$STASH/modules-load.d"

KEYS='net\.bridge\.bridge-nf-call-iptables|net\.ipv6\.conf\.all\.forwarding|net\.ipv4\.ip_forward|net\.netfilter\.nf_conntrack_max'

# Stash persistent config that already sets these values.
for f in /etc/sysctl.d/*.conf; do
  [ -f "$f" ] && [ ! -L "$f" ] || continue
  grep -qE "^[[:space:]]*($KEYS)[[:space:]]*=" "$f" && mv -f "$f" "$STASH/sysctl.d/"
done
if [ -f /etc/sysctl.conf ] && grep -qE "^[[:space:]]*($KEYS)[[:space:]]*=" /etc/sysctl.conf; then
  cp -f /etc/sysctl.conf "$STASH/sysctl.conf"
  sed -i -E "s/^([[:space:]]*($KEYS)[[:space:]]*=)/# \1/" /etc/sysctl.conf
fi
for f in /etc/modules-load.d/*.conf; do
  [ -f "$f" ] && [ ! -L "$f" ] || continue
  grep -qwE '^[[:space:]]*(overlay|br_netfilter)' "$f" && mv -f "$f" "$STASH/modules-load.d/"
done

# Live values away from target (ip_forward left alone: turning it off breaks Pod traffic).
sysctl -w net.netfilter.nf_conntrack_max=65536 >/dev/null 2>&1
sysctl -w net.ipv6.conf.all.forwarding=0 >/dev/null 2>&1
sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1
modprobe -r br_netfilter >/dev/null 2>&1

# Build the package.
B=/tmp/cka-shim-build
rm -rf "$B"
mkdir -p "$B/DEBIAN" "$B/lib/systemd/system" "$B/usr/local/bin"
cat > "$B/DEBIAN/control" <<'EOF'
Package: cka-shim
Version: 1.0
Architecture: all
Maintainer: cka-drill
Description: CKA drill container runtime shim
EOF
cat > "$B/usr/local/bin/cka-shim" <<'EOF'
#!/bin/sh
exec sleep infinity
EOF
chmod 755 "$B/usr/local/bin/cka-shim"
cat > "$B/lib/systemd/system/cka-shim.service" <<'EOF'
[Unit]
Description=CKA drill runtime shim

[Service]
ExecStart=/usr/local/bin/cka-shim
Restart=always

[Install]
WantedBy=multi-user.target
EOF
dpkg-deb --build "$B" /root/cka-shim_1.0_all.deb >/dev/null
rm -rf "$B"

cat > /root/verify-prereqs.sh <<'EOF'
#!/usr/bin/env bash
# Verification supplied with the task. Run on this node.
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; }
t()    { if "${@:2}" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

t "package cka-shim installed"  bash -c "dpkg -s cka-shim | grep -q 'Status: install ok installed'"
t "service cka-shim active"     systemctl is-active --quiet cka-shim
t "service cka-shim enabled"    systemctl is-enabled --quiet cka-shim
t "overlay loaded"              bash -c "lsmod | grep -qw ^overlay || grep -qw overlay /proc/filesystems"
t "br_netfilter loaded"         bash -c "lsmod | grep -qw ^br_netfilter || [ -d /proc/sys/net/bridge ]"
t "overlay loads on boot"       bash -c "grep -rqsxE '[[:space:]]*overlay[[:space:]]*' /etc/modules-load.d/"
t "br_netfilter loads on boot"  bash -c "grep -rqsxE '[[:space:]]*br_netfilter[[:space:]]*' /etc/modules-load.d/"
for kv in net.bridge.bridge-nf-call-iptables=1 net.ipv6.conf.all.forwarding=1 net.ipv4.ip_forward=1 net.netfilter.nf_conntrack_max=131072; do
  k="${kv%=*}"; v="${kv#*=}"; re="${k//./\\.}"
  t "$k = $v (live)"       bash -c "[ \"\$(sysctl -n $k)\" = '$v' ]"
  t "$k = $v (persistent)" bash -c "grep -rhsE '^[[:space:]]*$re[[:space:]]*=[[:space:]]*$v[[:space:]]*$' /etc/sysctl.d/ /etc/sysctl.conf | grep -q ."
done
EOF
chmod 755 /root/verify-prereqs.sh
REMOTE

echo "seeded on $NODE."
