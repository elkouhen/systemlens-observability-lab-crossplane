#!/usr/bin/env bash
# Supprime les data streams OTel antérieurs à ADR-019, dont le namespace ne
# porte pas la plateforme : <type>-<dataset>.otel-<environnement> ou
# .otel-default. Un data stream n'est retenu que s'il n'a reçu aucun document
# depuis LEGACY_INACTIVE_WINDOW (30m par défaut). Sans CONFIRM=1, la liste est
# seulement affichée. Les data streams *-default de Fleet Server, sans
# suffixe .otel, ne sont jamais concernés.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant le nettoyage}"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
inactive_window="${LEGACY_INACTIVE_WINDOW:-30m}"
confirm="${CONFIRM:-0}"

request() {
  local method="$1" path="$2" body="${3:-}"
  curl --fail --silent --show-error \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X "${method}" "${elasticsearch_url}${path}" \
    ${body:+--data "${body}"}
}

# Namespace sans « _ » : pas de plateforme (ADR-019).
legacy=()
while IFS= read -r name; do
  [[ -n "${name}" ]] && legacy+=("${name}")
done < <(request GET '/_data_stream/*-*.otel-*?filter_path=data_streams.name' |
  jq -r '.data_streams[]?.name | select(test("\\.otel-[a-z0-9]+$"))' | sort)

if (( ${#legacy[@]} == 0 )); then
  printf 'Aucun data stream OTel sans plateforme.\n'
  exit 0
fi

recent_query="{\"query\":{\"range\":{\"@timestamp\":{\"gte\":\"now-${inactive_window}\"}}}}"
deletable=()
for name in "${legacy[@]}"; do
  recent="$(request POST "/${name}/_count" "${recent_query}" | jq -r '.count // 0')"
  if (( recent > 0 )); then
    printf 'ACTIF   %-60s %s document(s) depuis %s, conservé\n' "${name}" "${recent}" "${inactive_window}"
  else
    deletable+=("${name}")
    printf 'ANCIEN  %s\n' "${name}"
  fi
done

if (( ${#deletable[@]} == 0 )); then
  printf 'Aucun data stream inactif à supprimer.\n'
  exit 0
fi
if [[ "${confirm}" != 1 ]]; then
  printf '%s data stream(s) inactif(s). Relancer avec CONFIRM=1 pour les supprimer.\n' "${#deletable[@]}"
  exit 0
fi

for name in "${deletable[@]}"; do
  request DELETE "/_data_stream/${name}" | jq -e '.acknowledged == true' >/dev/null
  printf 'SUPPRIMÉ %s\n' "${name}"
done
