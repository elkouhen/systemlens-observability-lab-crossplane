#!/usr/bin/env bash
# Redémarre les services de transport des métriques sans reprovisionnement.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
kubectl_k3s=("${KUBECTL:-kubectl}" --kubeconfig "${architecture_root}/.kube/k3s.config")

command -v limactl >/dev/null || {
  printf 'Lima (limactl) est requis pour redémarrer la chaîne métriques.\n' >&2
  exit 2
}

cd "${architecture_root}"

run_remote() {
  local node="$1"
  local description="$2"
  local command="$3"

  printf '%s (%s)\n' "${description}" "${node}"
  "${vm_bin}" shell "${node}" "${command}"
}

# L'ordre limite la durée pendant laquelle les signaux sont acceptés sans
# transport disponible : buffer Kafka (Strimzi, k3s-01), exporteur backend,
# entrée OTLP, puis frontal Edge.
printf 'Redémarrage du Kafka OTel (k3s-01)\n'
"${kubectl_k3s[@]}" -n elastic-stack delete pod otel-kafka-dual-0 --wait=true
"${kubectl_k3s[@]}" -n elastic-stack wait --for=condition=Ready kafka/otel-kafka --timeout=300s
"${kubectl_k3s[@]}" -n elastic-stack wait --for=condition=Ready pod/otel-kafka-dual-0 --timeout=300s

printf 'Redémarrage du collecteur backend OTel (k3s-01)\n'
"${kubectl_k3s[@]}" -n elastic-stack rollout restart deployment/otel-backend
"${kubectl_k3s[@]}" -n elastic-stack rollout status deployment/otel-backend --timeout=180s

run_remote otel-edge-01 'Redémarrage du collecteur Edge' \
  'sudo systemctl restart observability-otel-edge && sudo systemctl is-active observability-otel-edge && for attempt in $(seq 1 30); do curl --fail --silent http://127.0.0.1:13135/ >/dev/null && exit 0; sleep 2; done; exit 1'

run_remote otel-edge-01 'Redémarrage de HAProxy OTLP' \
  'sudo haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null && sudo systemctl restart haproxy && sudo systemctl is-active haproxy'

printf 'Chaîne métriques redémarrée : exporteur backend → Kafka OTel → Edge → HAProxy.\n'
