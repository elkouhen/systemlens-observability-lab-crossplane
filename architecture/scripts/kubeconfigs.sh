#!/usr/bin/env bash
# Écrit les kubeconfig locaux (non versionnés) des trois clusters k3s, joignables depuis l'hôte par
# les redirections de port Lima (lima/<vm>.yaml) :
#   .kube/tools.config  hub tools-01   https://127.0.0.1:6443  (KUBECONFIG par défaut du Makefile)
#   .kube/k3s.config    k3s-01         https://127.0.0.1:6444
#   .kube/elk.config    elk-01         https://127.0.0.1:6445
set -euo pipefail

dir="${KUBE_DIR:-.kube}"
vm="${VM:-$(dirname "$0")/vm}"
mkdir -p "$dir"
umask 077
for entry in tools-01:tools:6443 k3s-01:k3s:6444 elk-01:elk:6445; do
  IFS=: read -r node file port <<<"$entry"
  target="$dir/$file.config"
  "$vm" shell "$node" 'sudo cat /etc/rancher/k3s/k3s.yaml' \
    | sed "s#https://127.0.0.1:6443#https://127.0.0.1:${port}#" > "$target.tmp"
  mv "$target.tmp" "$target"
  echo "Kubeconfig de $node écrit dans $target"
done
