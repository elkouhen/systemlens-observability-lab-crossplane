#!/usr/bin/env bash
# Redémarre les services de l'architecture dans l'ordre de leurs dépendances.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
kubectl_bin="${KUBECTL:-kubectl}"
kubeconfig_file="${K3S_KUBECONFIG:-${architecture_root}/.kube/k3s.config}"

command -v limactl >/dev/null || {
  printf 'Lima (limactl) est requis pour redémarrer les services.\n' >&2
  exit 2
}

cd "${architecture_root}"

restart_remote_services() {
  local node="$1"
  shift
  printf '\n=== Redémarrage %s ===\n' "${node}"
  for unit in "$@"; do
    printf 'Redémarrage de %s... ' "${unit}"
    "${vm_bin}" shell "${node}" "sudo systemctl restart ${unit} && sudo systemctl is-active --quiet ${unit}"
    printf 'actif\n'
  done
}

wait_remote_command() {
  local node="$1"
  local description="$2"
  local command="$3"

  printf 'Attente : %s (%s)\n' "${description}" "${node}"
  for attempt in $(seq 1 30); do
    if "${vm_bin}" shell "${node}" "${command}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  printf 'Délai dépassé : %s (%s)\n' "${description}" "${node}" >&2
  return 1
}

restart_remote_services supermarket-middleware-01 \
  observability-mongodb.service observability-kafka.service observability-postgresql.service \
  elastic-agent.service
wait_remote_command supermarket-middleware-01 'PostgreSQL' \
  'sudo podman exec observability-postgresql pg_isready -U observability -d observability_test'
wait_remote_command supermarket-middleware-01 'Kafka métier' \
  'sudo podman exec --env KAFKA_OPTS= observability-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list'

restart_remote_services otel-backend-01 \
  observability-otel-kafka.service observability-otel-backend.service \
  elastic-agent.service
wait_remote_command otel-backend-01 'Kafka OTel' \
  'sudo podman exec --env KAFKA_OPTS= observability-otel-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 --command-config /opt/kafka/config/otel-kafka-client.properties describe --status'
wait_remote_command otel-backend-01 'collecteur backend OTel' \
  'curl --fail --silent http://127.0.0.1:13134/'

restart_remote_services otel-edge-01 \
  haproxy.service observability-otel-edge.service elastic-agent.service
wait_remote_command otel-edge-01 'collecteur Edge OTel' \
  'curl --fail --silent http://127.0.0.1:13135/'

restart_remote_services elk-01 \
  observability-elasticsearch.service observability-kibana.service \
  observability-fleet-server.service \
  elastic-agent.service

restart_remote_services k3s-01 k3s.service
if [[ ! -r "${kubeconfig_file}" ]] || ! command -v "${kubectl_bin}" >/dev/null 2>&1; then
  printf 'Kubeconfig ou kubectl indisponible : %s\n' "${kubeconfig_file}" >&2
  exit 1
fi

printf '\n=== Attente du cluster Kubernetes ===\n'
for attempt in $(seq 1 30); do
  if KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" wait --for=condition=Ready node/k3s-01 --timeout=5s >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" -eq 30 ]]; then
    printf 'Le nœud k3s-01 n’est pas prêt.\n' >&2
    exit 1
  fi
  sleep 2
done

printf '\n=== Redémarrage des workloads applicatifs ===\n'
# kubectl ≥ 1.37 n'accepte plus --all pour rollout : les Deployments sont nommés explicitement.
for namespace in h0tl-supermarche-app h0tl-demo-app; do
  deployments="$(KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" -n "${namespace}" get deployment -o name)"
  [ -n "${deployments}" ] || continue
  # shellcheck disable=SC2086
  KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" -n "${namespace}" rollout restart ${deployments}
  for deployment in ${deployments}; do
    KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" -n "${namespace}" rollout status "${deployment}" --timeout=180s
  done
done

printf '\nTous les services de l’architecture ont été redémarrés et contrôlés.\n'
