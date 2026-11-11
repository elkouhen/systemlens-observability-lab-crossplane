#!/usr/bin/env bash
# Réconcilie un dashboard Kibana défini par l'API Dashboard sans le supprimer.
set -euo pipefail

dashboard_file="${1:?Usage : $0 <dashboard.json>}"

[[ -r "${dashboard_file}" ]] || { printf 'Fichier dashboard introuvable ou illisible : %s\n' "${dashboard_file}" >&2; exit 1; }

# Le script de déploiement utilise PUT pour l'API Dashboard et conserve donc
# l'ancien objet tant que la nouvelle définition n'est pas acceptée par Kibana.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/deploy-kibana-dashboard.sh" "${dashboard_file}"
