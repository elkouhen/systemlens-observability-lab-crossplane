#!/usr/bin/env bash
# Active le monitoring OpAMP des agents EDOT des VM sans modifier leur flux OTLP.
set -euo pipefail

readonly kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
readonly kibana_user="${KIBANA_USERNAME:-elastic}"
readonly kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
readonly fleet_url="${FLEET_URL:-http://fleet.observability.test:8220}"
readonly fleet_resolve="${FLEET_CURL_RESOLVE:-fleet.observability.test:8220:127.0.0.1}"
readonly fleet_vm_nodes="otel-edge-01 elk-01"

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de provisionner les VM Fleet}"

wait_for_fleet_server() {
  local status
  for attempt in $(seq 1 30); do
    status="$(curl --silent --show-error --insecure \
      --resolve "${fleet_resolve}" \
      "${fleet_url}/api/status" | jq -r '.status // empty' 2>/dev/null || true)"
    if [[ "${status}" == 'HEALTHY' ]]; then
      return 0
    fi
    sleep 2
  done
  printf 'Fleet Server indisponible ou non sain après 60 secondes\n' >&2
  return 1
}

wait_for_vm_agents() {
  local agents online missing
  for attempt in $(seq 1 30); do
    agents="$(curl --fail --silent --show-error --insecure \
      --resolve "${kibana_resolve}" \
      -u "${kibana_user}:${KIBANA_PASSWORD}" \
      "${kibana_url}/api/fleet/agents?perPage=1000")"
    online="$(jq -r --argjson nodes '["otel-edge-01","elk-01"]' '
      [.items[] | select(.local_metadata.host.hostname as $host | ($nodes | index($host)) != null and .status == "online") | .local_metadata.host.hostname]
      | unique | length
    ' <<<"${agents}")"
    if [[ "${online}" == '2' ]]; then
      return 0
    fi
    sleep 5
  done
  missing="$(jq -r --argjson nodes '["otel-edge-01","elk-01"]' '
    $nodes[] as $node | select(([.items[] | select(.local_metadata.host.hostname == $node and .status == "online")] | length) == 0) | $node
  ' <<<"${agents}" | paste -sd, -)"
  printf 'Agents OpAMP non online après 150 secondes : %s\n' "${missing:-inconnus}" >&2
  return 1
}

wait_for_fleet_server

# Le jeton ne transite que dans l'environnement du sous-processus de provisionnement.
# Le jeton ne transite jamais sur la ligne de commande ni dans le dépôt.
fleet_enrollment_keys="$(curl --fail --silent --show-error --insecure \
  --resolve "${kibana_resolve}" \
  -u "${kibana_user}:${KIBANA_PASSWORD}" \
  "${kibana_url}/api/fleet/enrollment_api_keys?perPage=1000")"

for node in ${fleet_vm_nodes}; do
  policy_id='otel-fleet'
  token_name="systemlens-opamp-${node}"
  response="$(jq -c --arg name "${token_name}" --arg policy "${policy_id}" \
    '.items[] | select((.name == $name or (.name | startswith($name + " ("))) and .policy_id == $policy and .active == true)' \
    <<<"${fleet_enrollment_keys}" | head -n 1)"
  if [[ -z "${response}" ]]; then
    response="$(curl --fail --silent --show-error --insecure \
      --resolve "${kibana_resolve}" \
      -u "${kibana_user}:${KIBANA_PASSWORD}" \
      -H 'kbn-xsrf: systemlens-fleet-vm-provision' \
      -H 'Content-Type: application/json' \
      -X POST \
      --data "{\"name\":\"${token_name}\",\"policy_id\":\"${policy_id}\"}" \
      "${kibana_url}/api/fleet/enrollment_api_keys")"
  fi
  token="$(jq -er '.item.api_key // .api_key // empty' <<<"${response}")"
  FLEET_ENROLLMENT_TOKEN="${token}" "${VM:-$(dirname "$0")/../../../scripts/vm}" provision "${node}" --playbook fleet-agent
done

wait_for_vm_agents
printf 'Monitoring OpAMP réconcilié : les agents VM %s sont online\n' "${fleet_vm_nodes}"
