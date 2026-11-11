#!/usr/bin/env bash
# Vérifie le routage par plateforme (ADR-015) sur les documents récents :
# chaque plateforme reçoit des logs et des métriques portant platform.id
# dans son namespace <plateforme>_<environnement> (ADR-019), les traces de
# l'application sont dans ce namespace, plus aucun document n'arrive dans un
# namespace default ou d'environnement seul, aucun ne
# porte otel.kafka.topic, et le collecteur Edge n'a rejeté aucune ressource.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"
: "${OTEL_PLATFORMS:?Définir OTEL_PLATFORMS, par exemple « k3s supermarche elk »}"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
window="${OBSERVABILITY_VERIFY_WINDOW:-15m}"
environment="${OTEL_ENVIRONMENT:-homologation}"

request() {
  local method="$1" path="$2" body="${3:-}"
  curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X "${method}" "${elasticsearch_url}${path}" \
    ${body:+--data "${body}"}
}

count_query() {
  local pattern="$1" query="$2"
  request POST "/${pattern}/_count?ignore_unavailable=true&allow_no_indices=true" "${query}" | jq -r '.count // 0'
}

recent_filter() {
  printf '{"range":{"@timestamp":{"gte":"now-%s"}}}' "${window}"
}

failures=0
check_zero() {
  local label="$1" count="$2"
  if [[ "${count}" == 0 ]]; then
    printf 'OK      %s\n' "${label}"
  else
    printf 'KO      %s : %s document(s)\n' "${label}" "${count}" >&2
    failures=1
  fi
}
check_positive() {
  local label="$1" count="$2"
  if [[ "${count}" -gt 0 ]]; then
    printf 'OK      %s : %s document(s)\n' "${label}" "${count}"
  else
    printf 'KO      %s : aucun document sur %s\n' "${label}" "${window}" >&2
    failures=1
  fi
}

# Tous les signaux sont OTel natifs (ADR-018) : platform.id est un attribut
# de ressource, métriques de l'agent Java et traces comprises.
for platform in ${OTEL_PLATFORMS}; do
  for type in logs metrics; do
    indices="${type}-*.otel-${platform}_${environment}"
    platform_filter="{\"term\":{\"resource.attributes.platform.id\":\"${platform}\"}}"
    count="$(count_query "${indices}" \
      "{\"query\":{\"bool\":{\"filter\":[$(recent_filter),${platform_filter}]}}}")"
    check_positive "${type} de la plateforme ${platform} dans ${indices} (platform.id)" "${count}"
  done
done

count="$(count_query "traces-generic.otel-supermarche_${environment}" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter),{\"term\":{\"resource.attributes.platform.id\":\"supermarche\"}}]}}}")"
check_positive "traces OTel natives dans traces-generic.otel-supermarche_${environment}" "${count}"

# Métriques agrégées de l'UI APM, calculées par le connecteur elasticapm.
count="$(count_query "metrics-service_transaction.1m.otel-supermarche_${environment}" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter)]}}}")"
check_positive "métriques APM agrégées dans metrics-service_transaction.1m.otel-supermarche_${environment}" "${count}"

# Aucun flux OTel ne passe plus par APM Server ni ne reste en namespace
# default. Fleet Server écrit ses propres data streams *-default.
count="$(count_query "logs-*.otel-default,metrics-*.otel-default,traces-*.otel-default,logs-*.otel-${environment},metrics-*.otel-${environment},traces-*.otel-${environment},traces-apm*,metrics-apm*,logs-apm*" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter)]}}}")"
check_zero "documents récents en namespace default, sans plateforme ou au format APM Server (ECS)" "${count}"

count="$(count_query "logs-*,metrics-*" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter),{\"exists\":{\"field\":\"resource.attributes.otel.kafka.topic\"}}]}}}")"
check_zero "attribut otel.kafka.topic indexé" "${count}"

count="$(count_query "logs-*,metrics-*" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter),{\"term\":{\"resource.attributes.platform.id\":\"pirate\"}}]}}}")"
check_zero "platform.id usurpé" "${count}"

# Ressources rejetées par filter/unrouted de l'Edge : les compteurs
# otelcol_processor_filter_*_filtered sont cumulés depuis le démarrage du
# collecteur. Un point récent strictement positif signale un oubli de table
# (namespace Kubernetes ou VM) depuis ce démarrage.
count="$(count_query "metrics-collectortelemetry.otel-*" \
  "{\"query\":{\"bool\":{\"filter\":[$(recent_filter),{\"term\":{\"resource.attributes.service.name\":\"otel-edge\"}},{\"query_string\":{\"query\":\"metrics.otelcol_processor_filter_\\\\*:>0\"}}]}}}")"
check_zero "points de ressources rejetées par l'Edge (otelcol_processor_filter_*)" "${count}"

if [[ "${failures}" == 0 ]]; then
  printf 'Routage par plateforme vérifié sur %s.\n' "${window}"
else
  printf 'Routage par plateforme : au moins un contrôle a échoué.\n' >&2
  exit 1
fi
