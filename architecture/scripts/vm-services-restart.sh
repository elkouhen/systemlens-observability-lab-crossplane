#!/usr/bin/env bash
# Redémarre les services de l'architecture dans l'ordre de leurs dépendances.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
kubectl_bin="${KUBECTL:-kubectl}"
kubeconfig_file="${K3S_KUBECONFIG:-${architecture_root}/.kube/k3s.config}"
kube_dir="${architecture_root}/.kube"

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

restart_remote_services otel-edge-01 \
  haproxy.service observability-otel-edge.service elastic-agent.service
wait_remote_command otel-edge-01 'collecteur Edge OTel' \
  'curl --fail --silent http://127.0.0.1:13135/'

# Clusters k3s : le hub d'abord (Argo CD, Crossplane), puis les clusters cibles. Les workloads
# (opérateurs, bases, Kafka, Elastic, collecteurs) redémarrent avec k3s.
for entry in tools-01:tools k3s-01:k3s elk-01:elk; do
  node="${entry%%:*}"
  restart_remote_services "${node}" k3s.service
  printf 'Attente du nœud %s\n' "${node}"
  for attempt in $(seq 1 60); do
    if "${kubectl_bin}" --kubeconfig "${kube_dir}/${entry#*:}.config" wait --for=condition=Ready "node/${node}" --timeout=5s >/dev/null 2>&1; then
      break
    fi
    if [[ "${attempt}" -eq 60 ]]; then
      printf 'Le nœud %s n’est pas prêt.\n' "${node}" >&2
      exit 1
    fi
    sleep 2
  done
done
restart_remote_services k3s-01 elastic-agent.service
restart_remote_services elk-01 elastic-agent.service

printf '\n=== Attente des back-ends de k3s-01 ===\n'
KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" -n h0tl-supermarche-app wait --for=condition=Ready \
  cluster.postgresql.cnpg.io/supermarket-postgresql kafka/supermarket-kafka --timeout=300s
KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" -n elastic-stack wait --for=condition=Ready kafka/otel-kafka --timeout=300s

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
