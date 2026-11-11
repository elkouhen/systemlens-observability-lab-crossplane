#!/usr/bin/env bash
# Affiche l'état des services attendus sur chaque VM de l'architecture.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
kubectl_bin="${KUBECTL:-kubectl}"
kube_dir="${architecture_root}/.kube"

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

run_remote_status tools-01 k3s.service

run_remote_status k3s-01 k3s.service elastic-agent.service

run_remote_status elk-01 k3s.service elastic-agent.service

# Workloads des trois clusters : hub (Argo CD, Crossplane), k3s-01 (services, back-ends,
# collecteurs) et elk-01 (Elasticsearch, Kibana, Fleet Server).
for cluster in tools k3s elk; do
  printf '\n=== Workloads Kubernetes (%s) ===\n' "${cluster}"
  if [[ -r "${kube_dir}/${cluster}.config" ]] && command -v "${kubectl_bin}" >/dev/null 2>&1; then
    "${kubectl_bin}" --kubeconfig "${kube_dir}/${cluster}.config" get pods --all-namespaces -o wide || true
  else
    printf 'Kubeconfig ou kubectl indisponible : %s\n' "${kube_dir}/${cluster}.config"
  fi
done
