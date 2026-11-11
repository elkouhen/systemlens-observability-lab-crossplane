#!/usr/bin/env bash
# Vérifie les champs PostgreSQL OTel utilisés par les dashboards et réellement collectés.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la vérification}"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
window="${DASHBOARDS_VERIFY_WINDOW:-15m}"
end_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
  start_time="$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ')"
else
  start_time="$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')"
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/postgresql-otel-dashboard-ids.sh"

field_caps="$(curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
  "${elasticsearch_url}/metrics-postgresqlreceiver.otel-*/_field_caps?fields=postgresql.*")"

expected_fields=(
  postgresql.backends
  postgresql.connection.max
  postgresql.commits
  postgresql.rollbacks
  postgresql.database.count
  postgresql.database.name
  postgresql.table.count
  postgresql.db_size
  postgresql.bgwriter.maxwritten
  postgresql.bgwriter.buffers.allocated
  postgresql.bgwriter.buffers.writes
  postgresql.bgwriter.checkpoint.count
  postgresql.bgwriter.duration
  postgresql.blks_hit
  postgresql.blks_read
  postgresql.database.locks
  postgresql.temp_files
  postgresql.tup_inserted
  postgresql.tup_fetched
  postgresql.tup_returned
)

missing=0
for field in "${expected_fields[@]}"; do
  if jq -e --arg field "${field}" '.fields | has($field)' <<<"${field_caps}" >/dev/null; then
    printf 'OK      champ %-42s présent dans le mapping\n' "${field}"
  else
    printf 'ABSENT  champ %-42s absent du mapping\n' "${field}" >&2
    missing=1
  fi
done

for field in postgresql.backends postgresql.commits postgresql.rollbacks postgresql.db_size; do
  count_response="$(curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/metrics-postgresqlreceiver.otel-*/_count" \
    --data "{\"query\":{\"bool\":{\"filter\":[{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},{\"exists\":{\"field\":\"${field}\"}}]}}}")"
  count="$(jq -r '.count // 0' <<<"${count_response}")"
  if (( count > 0 )); then
    printf 'OK      données %-36s %s document(s) sur %s\n' "${field}" "${count}" "${window}"
  else
    printf 'ABSENT  données %-36s aucun document sur %s\n' "${field}" "${window}" >&2
    missing=1
  fi
done

load_postgresql_otel_dashboard_ids
for dashboard_id in "${dashboard_ids[@]}"; do
  dashboard_json="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"
  while IFS= read -r panel; do
    panel_title="$(jq -r '.title' <<<"${panel}")"
    query="$(jq -r '.query' <<<"${panel}")"
    normalized_query="$(printf '%s' "${query}" | sed "s/?_tstart/TO_DATETIME(\"${start_time}\")/g; s/?_tend/TO_DATETIME(\"${end_time}\")/g")"
    query_response="$(curl --silent --show-error --insecure \
      --resolve "${elasticsearch_resolve}" \
      -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -X POST "${elasticsearch_url}/_query" \
      --data "$(jq -cn --arg query "${normalized_query}" '{query:$query}')")"
    if jq -e '.error != null' <<<"${query_response}" >/dev/null; then
      printf 'ERREUR  dashboard %-32s panneau %-38s ES|QL: %s\n' "${dashboard_id}" "${panel_title}" "$(jq -r '.error.reason // .error.type // "erreur inconnue"' <<<"${query_response}" | tr '\n' ' ')" >&2
      missing=1
    else
      query_fields="$(jq -c '[.columns[]?.name] | unique' <<<"${query_response}")"
      while IFS= read -r lens_field; do
        [[ -n "${lens_field}" ]] || continue
        if ! jq -n -e --arg field "${lens_field}" --argjson fields "${query_fields}" \
          'any($fields[]; . == $field)' \
          >/dev/null; then
          printf 'ERREUR  dashboard %-32s panneau %-38s colonne Lens obsolète : %s\n' \
            "${dashboard_id}" "${panel_title}" "${lens_field}" >&2
          missing=1
        fi
      done < <(jq -r '.lens_fields[]?' <<<"${panel}")
      printf 'OK      dashboard %-32s panneau %-38s ES|QL valide\n' "${dashboard_id}" "${panel_title}"
    fi
  done < <(jq -c '.attributes.panelsJSON | fromjson[] |
    {title:.embeddableConfig.attributes.title,
     query:(.embeddableConfig.attributes.state.query.esql // ([.embeddableConfig.attributes.state.datasourceStates.textBased.layers[]?.query.esql][0] // "")),
     lens_fields:[.embeddableConfig.attributes.state.datasourceStates.textBased.layers[]?.columns[]?.fieldName] | unique} |
    select(.query != "")' <<<"${dashboard_json}")
done

if (( missing )); then
  printf 'La vérification PostgreSQL OTel a détecté au moins une métrique absente ou une requête invalide.\n' >&2
  exit 1
fi

printf 'Les métriques et requêtes des dashboards PostgreSQL OTel sont compatibles.\n'
