#!/usr/bin/env bash
# Redémarre les services de transport des métriques sans reprovisionnement.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
kubectl_k3s=("${KUBECTL:-kubectl}" --kubeconfig "${architecture_root}/.kube/k3s.config")

# L'ordre limite la durée pendant laquelle les signaux sont acceptés sans
# transport disponible : buffer Kafka (Strimzi, k3s-01), exporteur backend,
# puis entrée OTLP (Collecteur Edge).
printf 'Redémarrage du Kafka OTel (k3s-01)\n'
"${kubectl_k3s[@]}" -n elastic-stack delete pod otel-kafka-dual-0 --wait=true
"${kubectl_k3s[@]}" -n elastic-stack wait --for=condition=Ready kafka/otel-kafka --timeout=300s
"${kubectl_k3s[@]}" -n elastic-stack wait --for=condition=Ready pod/otel-kafka-dual-0 --timeout=300s

printf 'Redémarrage du collecteur backend OTel (k3s-01)\n'
"${kubectl_k3s[@]}" -n elastic-stack rollout restart deployment/otel-backend
"${kubectl_k3s[@]}" -n elastic-stack rollout status deployment/otel-backend --timeout=180s

printf 'Redémarrage du Collecteur Edge (k3s-01)\n'
"${kubectl_k3s[@]}" -n elastic-stack rollout restart deployment/otel-edge
"${kubectl_k3s[@]}" -n elastic-stack rollout status deployment/otel-edge --timeout=180s

printf 'Chaîne métriques redémarrée : Kafka OTel → exporteur backend → Edge.\n'
