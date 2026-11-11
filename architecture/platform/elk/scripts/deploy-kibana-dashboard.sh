#!/usr/bin/env bash
# Importe un export NDJSON Kibana de manière idempotente.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/.." && pwd)"
dashboard_file="${1:?Usage : $0 <export.ndjson>}"
kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"

[[ -r "${dashboard_file}" ]] || {
  printf 'Fichier dashboard introuvable ou illisible : %s\n' "${dashboard_file}" >&2
  exit 1
}
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de déployer le dashboard}"

response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT

# Les dashboards métier utilisent l'API Dashboard Kibana (définitions inline
# ES|QL). Les autres fichiers restent des exports NDJSON Saved Objects.
if jq -e '(.panels? | type == "array")' "${dashboard_file}" >/dev/null 2>&1; then
  dashboard_id="$(jq -er '.id' "${dashboard_file}")"
  dashboard_payload="$(jq -c 'del(.id)' "${dashboard_file}")"
  http_status=000
  response=''
  for attempt in $(seq 1 12); do
    http_status="$(curl --silent --show-error --insecure \
      --resolve "${kibana_resolve}" \
      -u "${kibana_user}:${KIBANA_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -H 'Elastic-Api-Version: 2023-10-31' \
      -H 'kbn-xsrf: systemlens-dashboard-deploy' \
      -X PUT --data "${dashboard_payload}" \
      -o "${response_file}" -w '%{http_code}' \
      "${kibana_url}/api/dashboards/${dashboard_id}" || true)"
    response="$(<"${response_file}")"
    if [[ "${http_status}" =~ ^2[0-9][0-9]$ ]] && \
       jq -e '.data.title and (.data.panels | type == "array")' >/dev/null 2>&1 <<<"${response}"; then
      printf 'Dashboard Kibana API réconcilié : %s.\n' "${dashboard_id}"
      exit 0
    fi
    if [[ ! "${http_status}" =~ ^5[0-9][0-9]$ ]] && [[ "${http_status}" != 000 ]]; then
      break
    fi
    sleep 5
  done
  printf 'Échec de la réconciliation du dashboard Kibana API :\n%s\n' "${response}" >&2
  exit 1
fi

http_status=000
response=''
for attempt in $(seq 1 12); do
  http_status="$(curl --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'kbn-xsrf: systemlens-dashboard-deploy' \
    -F "file=@${dashboard_file};type=application/ndjson" \
    -o "${response_file}" -w '%{http_code}' \
    "${kibana_url}/api/saved_objects/_import?overwrite=true" || true)"
  response="$(<"${response_file}")"
  if [[ "${http_status}" =~ ^2[0-9][0-9]$ ]] && \
     jq -e '.success == true and ((.errors // []) | length == 0)' >/dev/null <<<"${response}"; then
    printf 'Dashboard Kibana importé ou mis à jour : %s objet(s).\n' \
      "$(jq -r '.successCount // 0' <<<"${response}")"
    exit 0
  fi
  if [[ ! "${http_status}" =~ ^5[0-9][0-9]$ ]] && [[ "${http_status}" != 000 ]]; then
    break
  fi
  sleep 5
done

if ! jq -e '.success == true and ((.errors // []) | length == 0)' >/dev/null <<<"${response}"; then
  printf 'Échec de l’import du dashboard Kibana :\n%s\n' "${response}" >&2
  exit 1
fi
