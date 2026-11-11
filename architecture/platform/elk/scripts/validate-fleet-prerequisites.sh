#!/usr/bin/env bash
# Vérifie les préconditions du plan de contrôle Elastic avant Fleet.
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
fleet_url="${FLEET_URL:-http://fleet.observability.test:8220}"
fleet_resolve="${FLEET_CURL_RESOLVE:-fleet.observability.test:8220:127.0.0.1}"
kibana_password="${KIBANA_PASSWORD:-${ELASTICSEARCH_PASSWORD:-}}"
elasticsearch_password="${ELASTICSEARCH_PASSWORD:-${KIBANA_PASSWORD:-}}"

: "${kibana_password:?Définir KIBANA_PASSWORD ou ELASTICSEARCH_PASSWORD avant le préflight Fleet}"
: "${elasticsearch_password:?Définir ELASTICSEARCH_PASSWORD ou KIBANA_PASSWORD avant le préflight Fleet}"

curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "elastic:${elasticsearch_password}" \
  "${elasticsearch_url}/_security/_authenticate" >/dev/null

curl --fail --silent --show-error --insecure \
  --resolve "${kibana_resolve}" \
  -u "elastic:${kibana_password}" \
  -H 'kbn-xsrf: systemlens-fleet-preflight' \
  "${kibana_url}/api/fleet/agent_policies?perPage=1" >/dev/null

fleet_status="$(curl --fail --silent --show-error --insecure \
  --resolve "${fleet_resolve}" \
  "${fleet_url}/api/status" | jq -r '.status // empty')"
[[ "${fleet_status}" == 'HEALTHY' ]] || {
  printf 'Fleet Server n’est pas HEALTHY : %s\n' "${fleet_status:-inconnu}" >&2
  exit 1
}

printf 'Préconditions Elastic, Kibana et Fleet satisfaites\n'
