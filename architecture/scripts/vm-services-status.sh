#!/usr/bin/env bash
# Affiche l'état des services attendus sur chaque VM de l'architecture.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
kubectl_bin="${KUBECTL:-kubectl}"
kubeconfig_file="${K3S_KUBECONFIG:-${architecture_root}/.kube/k3s.config}"

command -v limactl >/dev/null || {
  printf 'Lima (limactl) est requis pour afficher l’état des services.\n' >&2
  exit 2
}

cd "${architecture_root}"

run_remote_status() {
  local node="$1"
  shift
  local units=("$@")
  local unit_list="${units[*]}"

  printf '\n=== %s ===\n' "${node}"
  printf '%s\n' 'Services systemd :'
  "${vm_bin}" shell "${node}" "sudo bash -s -- ${unit_list}" <<'REMOTE'
set +e
printf '%-42s %s\n' 'UNIT' 'ETAT'
printf '%-42s %s\n' '----' '----'
for unit in "$@"; do
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  printf '%-42s %s\n' "$unit" "${state:-unknown}"
done
printf '\nConteneurs Podman :\n'
if command -v podman >/dev/null 2>&1; then
  podman ps --all --format '{{.Names}}\t{{.Status}}\t{{.Image}}' || true
else
  printf 'podman\tabsent\n'
fi
REMOTE
}

run_remote_status supermarket-middleware-01 \
  observability-mongodb.service observability-kafka.service observability-postgresql.service \
  elastic-agent.service

run_remote_status otel-backend-01 \
  observability-otel-kafka.service observability-otel-backend.service \
  elastic-agent.service

run_remote_status otel-edge-01 \
  haproxy.service observability-otel-edge.service elastic-agent.service

run_remote_status elk-01 \
  observability-elasticsearch.service observability-kibana.service \
  observability-fleet-server.service \
  elastic-agent.service

run_remote_status k3s-01 k3s.service

printf '\n=== Workloads Kubernetes sur k3s-01 ===\n'
if [[ -r "${kubeconfig_file}" ]] && command -v "${kubectl_bin}" >/dev/null 2>&1; then
  KUBECONFIG="${kubeconfig_file}" "${kubectl_bin}" get pods --all-namespaces -o wide || true
else
  printf 'Kubeconfig ou kubectl indisponible : %s\n' "${kubeconfig_file}"
fi
