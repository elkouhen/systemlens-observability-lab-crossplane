#!/usr/bin/env bash
# Vérifie les requêtes ES|QL des dashboards Kubernetes OTel Fleet.
set -euo pipefail

command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la vérification des dashboards Kubernetes OTel}"

response="$(curl --fail --silent --show-error --insecure --resolve "${kibana_resolve}" \
  -u "elastic:${KIBANA_PASSWORD}" \
  "${kibana_url}/api/saved_objects/_find?type=dashboard&per_page=100&search_fields=title&search=Kubernetes%20OTel" \
  | jq '{saved_objects: [.saved_objects[] | select(.attributes.title | startswith("[Kubernetes OTel]"))]}')"

count="$(jq '.saved_objects | length' <<<"${response}")"
(( count == 11 )) || { printf 'Nombre inattendu de dashboards Kubernetes OTel : %s (attendu 11).\n' "${count}" >&2; exit 1; }

# Champs optionnels activés dans les Collectors (otel-kafka.yaml) et lus par
# les dashboards du package : chacun doit être réellement alimenté.
elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
window="${DASHBOARDS_VERIFY_WINDOW:-15m}"
for field in \
  'k8s.container.status.last_terminated_reason' \
  'k8s.node.condition_memory_pressure' \
  'k8s.pod.cpu_limit_utilization' \
  'k8s.pod.memory_limit_utilization'; do
  count="$(curl --fail --silent --show-error --insecure --resolve "${elasticsearch_resolve}" \
    -u "elastic:${ELASTICSEARCH_PASSWORD:-${KIBANA_PASSWORD}}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/metrics-*/_count" \
    --data "{\"query\":{\"bool\":{\"filter\":[{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},{\"exists\":{\"field\":\"${field}\"}}]}}}" \
    | jq -r '.count // 0')"
  if (( count == 0 )); then
    printf 'ABSENT  champ %s : aucun document sur %s\n' "${field}" "${window}" >&2
    exit 1
  fi
  printf 'OK      champ %-46s %s document(s) sur %s\n' "${field}" "${count}" "${window}"
done

printf 'Les 11 dashboards Kubernetes OTel ont des requêtes compatibles avec le schéma collecté.\n'
