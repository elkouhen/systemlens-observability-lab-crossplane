#!/usr/bin/env bash
# Redémarre les quatre VM Lima de l'architecture sans reprovisionnement Ansible.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
architecture_root="$(cd -- "${script_dir}/.." && pwd)"
vm_bin="${VM:-${script_dir}/vm}"
nodes=(tools-01 k3s-01 elk-01 otel-edge-01)

cd "${architecture_root}"

for node in "${nodes[@]}"; do
  state="$("${vm_bin}" state "${node}")"
  case "${state}" in
    Running)
      printf 'Redémarrage de %s\n' "${node}"
      "${vm_bin}" restart "${node}"
      ;;
    Stopped|Broken)
      printf 'Démarrage de %s (état : %s)\n' "${node}" "${state}"
      "${vm_bin}" up "${node}" --no-provision
      ;;
    *)
      printf 'État Lima inattendu pour %s : %s\n' "${node}" "${state:-inconnu}" >&2
      exit 1
      ;;
  esac
done

printf '\nÉtat final des VM :\n'
"${vm_bin}" status "${nodes[@]}"
