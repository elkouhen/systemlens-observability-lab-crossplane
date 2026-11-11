#!/usr/bin/env bash
set -euo pipefail

profile=minimal
data_node="${MIDDLEWARE_VM_NAME:-supermarket-middleware-01}"
nodes=("${data_node}")

run_on_vm() {
  local node="$1"
  shift
  "${VM:-$(dirname "$0")/../architecture/scripts/vm}" shell "$node" "$*"
}

printf '== Conteneurs Podman ==\n'
for node in "${nodes[@]}"; do
  printf '\n[%s]\n' "$node"
  if ! run_on_vm "$node" "sudo podman ps -a --format '{{.Names}} {{.Status}}'"; then
    printf 'VM indisponible ou Podman non installe\n'
  fi
done

printf '\n== MongoDB standalone ==\n'
run_on_vm "${data_node}" "timeout 15 sudo podman exec observability-mongodb mongosh --quiet --eval 'db.adminCommand({ping: 1}).ok'" \
  || printf 'MongoDB indisponible\n'

printf '\n== Kafka KRaft quorum ==\n'
for node in "${nodes[@]}"; do
  printf '\n[%s]\n' "$node"
  run_on_vm "$node" \
    'timeout 15 sudo podman exec -e KAFKA_OPTS= observability-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status' \
    || printf 'Kafka indisponible ou quorum non forme\n'
done

printf '\n== PostgreSQL %s ==\n' "${data_node}"
run_on_vm "${data_node}" \
  'timeout 15 sudo podman exec observability-postgresql psql -U observability -d observability_test -tAc "SELECT CASE WHEN to_regclass('\''public.stock_movements'\'') IS NULL THEN '\''PostgreSQL OK ; stock_movements absente (workload applicatif non initialise)'\'' ELSE '\''PostgreSQL OK ; stock_movements presente'\'' END"' \
  || printf 'PostgreSQL indisponible ou table stock_movements non créée\n'
