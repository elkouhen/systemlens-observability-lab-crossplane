#!/usr/bin/env bash
# Réconcilie les SLO et règles d'alerte architecture depuis un manifeste versionné.
set -euo pipefail

policy_file="${1:?Usage : $0 <observability-policies.json>}"
kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"

[[ -r "${policy_file}" ]] || { printf 'Manifest introuvable : %s\n' "${policy_file}" >&2; exit 1; }
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de synchroniser les politiques}"

jq -e '(.slos | type == "array") and (.rules | type == "array")' "${policy_file}" >/dev/null

request() {
  local method="$1" path="$2" body="$3" response status
  response="$(mktemp)"
  status="$(curl --silent --show-error --insecure --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" -H 'Content-Type: application/json' \
    -H 'kbn-xsrf: systemlens-observability-policy' -X "${method}" \
    --data "${body}" -o "${response}" -w '%{http_code}' "${kibana_url}${path}" || true)"
  if [[ ! "${status}" =~ ^2[0-9][0-9]$ ]]; then
    printf 'Échec %s %s (HTTP %s) :\n%s\n' "${method}" "${path}" "${status}" "$(<"${response}")" >&2
    rm -f "${response}"
    return 1
  fi
  rm -f "${response}"
}

while IFS= read -r slo; do
  id="$(jq -r '.id' <<<"${slo}")"
  response="$(mktemp)"
  exists="$(curl --silent --show-error --insecure --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" -o "${response}" -w '%{http_code}' \
    "${kibana_url}/api/observability/slos/${id}" || true)"
  if [[ "${exists}" == 403 ]] && jq -e '.message | test("license"; "i")' "${response}" >/dev/null 2>&1; then
    printf 'SLO ignoré (licence Platinum requise) : %s\n' "${id}"
    rm -f "${response}"
    continue
  fi
  rm -f "${response}"
  if [[ "${exists}" == 404 ]]; then
    request POST '/api/observability/slos' "${slo}"
  elif [[ "${exists}" =~ ^2[0-9][0-9]$ ]]; then
    # L'identifiant est accepté à la création, mais il est porté par le chemin
    # et refusé comme clé supplémentaire par le schéma de mise à jour Kibana.
    update_slo="$(jq -c 'del(.id)' <<<"${slo}")"
    request PUT "/api/observability/slos/${id}" "${update_slo}"
  else
    printf 'Impossible de lire le SLO %s (HTTP %s).\n' "${id}" "${exists}" >&2
    exit 1
  fi
  printf 'SLO réconcilié : %s\n' "${id}"
done < <(jq -c '.slos[]' "${policy_file}")

while IFS= read -r rule; do
  id="$(jq -r '.id' <<<"${rule}")"
  body="$(jq -c '.body' <<<"${rule}")"
  exists="$(curl --silent --show-error --insecure --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" -o /dev/null -w '%{http_code}' \
    "${kibana_url}/api/alerting/rule/${id}" || true)"
  if [[ "${exists}" == 404 ]]; then
    request POST "/api/alerting/rule/${id}" "${body}"
  elif [[ "${exists}" =~ ^2[0-9][0-9]$ ]]; then
    # Le type et le consumer sont requis à la création, mais immuables et
    # refusés par le schéma de mise à jour Kibana.
    update_body="$(jq -c 'del(.rule_type_id, .consumer)' <<<"${body}")"
    request PUT "/api/alerting/rule/${id}" "${update_body}"
  else
    printf 'Impossible de lire la règle %s (HTTP %s).\n' "${id}" "${exists}" >&2
    exit 1
  fi
  printf 'Règle réconciliée : %s\n' "${id}"
done < <(jq -c '.rules[]' "${policy_file}")
