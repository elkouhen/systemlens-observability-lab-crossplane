#!/usr/bin/env bash
set -euo pipefail

target="${K3S_KUBECONFIG:-.kube/k3s.config}"
k3s_ip="${K3S_VM_IP:-127.0.0.1}"
mkdir -p "$(dirname "$target")"
umask 077
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

"${VM:-$(dirname "$0")/vm}" shell k3s-01 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$tmp"
sed "s#https://127.0.0.1:6443#https://${k3s_ip}:6443#" "$tmp" > "$target"
chmod 600 "$target"
echo "Kubeconfig k3s écrit dans $target"
