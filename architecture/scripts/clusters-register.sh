#!/usr/bin/env bash
# Enregistre les clusters cibles k3s-01 et elk-01 dans le hub tools-01 (make clusters-register) :
# - Secret argocd/cluster-<nom> (label argocd.argoproj.io/secret-type=cluster) : destination des
#   Application Argo CD (destination.name) ;
# - Secret crossplane-system/cluster-<nom> (clé kubeconfig) : ClusterProviderConfig <nom> de
#   provider-kubernetes (gitops/crossplane/install/clusters.yaml).
# Les identifiants (certificat client administrateur de k3s) sont lus dans chaque VM et pointent sur
# l'IP privée du nœud (192.168.33.x), joignable depuis le hub. k3s les régénère à chaque
# installation : ils ne sont pas versionnés (SOPS imposerait de rechiffrer à chaque reconstruction).
set -euo pipefail

kubectl="${KUBECTL:-kubectl}"
vm="${VM:-$(dirname "$0")/vm}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$kubectl" create namespace argocd --dry-run=client -o yaml | "$kubectl" apply -f - >/dev/null
"$kubectl" create namespace crossplane-system --dry-run=client -o yaml | "$kubectl" apply -f - >/dev/null
for entry in k3s-01:192.168.33.50 elk-01:192.168.33.40; do
  IFS=: read -r name ip <<<"$entry"
  server="https://$ip:6443"
  "$vm" shell "$name" 'sudo cat /etc/rancher/k3s/k3s.yaml' \
    | sed "s#https://127.0.0.1:6443#$server#" > "$tmp/$name.yaml"
  ca=$(awk '/certificate-authority-data:/ {print $2}' "$tmp/$name.yaml")
  cert=$(awk '/client-certificate-data:/ {print $2}' "$tmp/$name.yaml")
  key=$(awk '/client-key-data:/ {print $2}' "$tmp/$name.yaml")
  [ -n "$ca" ] && [ -n "$cert" ] && [ -n "$key" ] || { echo "Kubeconfig de $name incomplet" >&2; exit 1; }
  jq -cn --arg ca "$ca" --arg cert "$cert" --arg key "$key" \
    '{tlsClientConfig: {caData: $ca, certData: $cert, keyData: $key}}' > "$tmp/$name.json"
  "$kubectl" -n argocd create secret generic "cluster-$name" \
    --from-literal=name="$name" --from-literal=server="$server" --from-file=config="$tmp/$name.json" \
    --dry-run=client -o yaml \
    | "$kubectl" label --local -f - argocd.argoproj.io/secret-type=cluster -o yaml \
    | "$kubectl" apply -f - >/dev/null
  "$kubectl" -n crossplane-system create secret generic "cluster-$name" \
    --from-file=kubeconfig="$tmp/$name.yaml" --dry-run=client -o yaml | "$kubectl" apply -f - >/dev/null
  echo "Cluster $name ($server) enregistré dans Argo CD et provider-kubernetes"
done
