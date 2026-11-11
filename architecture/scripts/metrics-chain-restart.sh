#!/usr/bin/env bash
# Redémarre les services de transport des métriques sans reprovisionnement.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"

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
# transport disponible : buffer Kafka, exporteur backend, entrée OTLP, puis
# frontal Edge.
run_remote otel-backend-01 'Redémarrage du Kafka OTel' \
  'sudo systemctl restart observability-otel-kafka && sudo systemctl is-active observability-otel-kafka && for attempt in $(seq 1 30); do sudo podman exec -e KAFKA_OPTS= observability-otel-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 --command-config /opt/kafka/config/otel-kafka-client.properties describe --status >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'

run_remote otel-backend-01 'Redémarrage du collecteur backend OTel' \
  'sudo systemctl restart observability-otel-backend && sudo systemctl is-active observability-otel-backend && for attempt in $(seq 1 30); do curl --fail --silent http://127.0.0.1:13134/ >/dev/null && exit 0; sleep 2; done; exit 1'

run_remote otel-edge-01 'Redémarrage du collecteur Edge' \
  'sudo systemctl restart observability-otel-edge && sudo systemctl is-active observability-otel-edge && for attempt in $(seq 1 30); do curl --fail --silent http://127.0.0.1:13135/ >/dev/null && exit 0; sleep 2; done; exit 1'

run_remote otel-edge-01 'Redémarrage de HAProxy OTLP' \
  'sudo haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null && sudo systemctl restart haproxy && sudo systemctl is-active haproxy'

printf 'Chaîne métriques redémarrée : exporteur backend → Kafka OTel → Edge → HAProxy.\n'
