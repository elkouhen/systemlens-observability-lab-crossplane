#!/usr/bin/env bash
# Vérifie la propagation W3C et le contrat OTel des données indexées : traces
# et erreurs au modèle d'APM Server, logs et métriques OTel natifs (ADR-012).
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"

mode="${1:-}"
case "${mode}" in
  schema|trace-context) ;;
  *)
    printf 'Usage : %s schema|trace-context\n' "$0" >&2
    exit 2
    ;;
esac

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
window="${OBSERVABILITY_VERIFY_WINDOW:-30m}"

request() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "${body}" ]]; then
    curl --fail --silent --show-error --insecure \
      --resolve "${elasticsearch_resolve}" \
      -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -X "${method}" "${elasticsearch_url}${path}" \
      --data "${body}"
  else
    curl --fail --silent --show-error --insecure \
      --resolve "${elasticsearch_resolve}" \
      -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
      -X "${method}" "${elasticsearch_url}${path}"
  fi
}

count_query() {
  local pattern="$1" query="$2"
  request POST "/${pattern}/_count" "${query}" | jq -r '.count // 0'
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

if [[ "${mode}" == trace-context ]]; then
  # Configuration déclarative de l'agent Java, commune aux trois services
  # (OTEL_CONFIG_FILE) : propagateurs W3C et export OTLP des logs.
  agent_config="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../gitops/supermarket" && pwd)/otel-agent.yaml"
  for key in tracecontext baggage logger_provider; do
    grep -Eq "^ *(- )?${key}:" "${agent_config}" || {
      printf 'KO      %s absent de %s\n' "${key}" "${agent_config}" >&2
      failures=1
    }
  done
  if [[ "${failures}" == 0 ]]; then
    printf 'OK      propagateurs W3C et export OTLP des logs configurés pour les trois services\n'
  fi

  trace_query="$(jq -cn --arg window "${window}" '{
    size: 0,
    query: {range: {"@timestamp": {gte: ("now-" + $window)}}},
    aggs: {
      trace_ids: {
        terms: {field: "trace.id", size: 500, min_doc_count: 2},
        aggs: {
          services: {terms: {field: "service.name", size: 20}},
          kafka: {filter: {bool: {should: [
            {term: {"span.subtype": "kafka"}},
            {term: {"span.type": "messaging"}},
            {wildcard: {"span.name": "*kafka*"}}
          ], minimum_should_match: 1}}}
        }
      }
    }
  }')"
  trace_response="$(request POST '/traces-*/_search' "${trace_query}")"
  trace_ids="$(jq -c '[.aggregations.trace_ids.buckets[]
    | select(([.services.buckets[].key] | index("order-service")) != null)
    | select(([.services.buckets[].key] | index("inventory-service")) != null)
    | select(.kafka.doc_count > 0)
    | .key]' <<<"${trace_response}")"
  if [[ "$(jq 'length' <<<"${trace_ids}")" == 0 ]]; then
    printf 'KO      aucun trace.id ne relie order-service, inventory-service et un span Kafka sur %s\n' "${window}" >&2
    failures=1
  else
    printf 'OK      trace.id partagé entre REST/Kafka et les services applicatifs sur %s\n' "${window}"
    # Les logs OTel natifs portent le contexte de trace dans trace_id/span_id,
    # posés par l'agent sur chaque log émis dans un span. Parmi les traces
    # retenues, au moins une doit avoir des logs corrélés.
    logs_query="$(jq -cn --argjson trace_ids "${trace_ids}" --arg window "${window}" '{
      size: 0,
      query: {bool: {filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {terms: {"trace_id": $trace_ids}},
        {exists: {field: "span_id"}}
      ]}},
      aggs: {trace_ids: {terms: {field: "trace_id", size: 1}}}
    }')"
    logs_response="$(request POST '/logs-generic.otel-supermarche_*/_search?allow_no_indices=true' "${logs_query}")"
    correlated="$(jq -r '.aggregations.trace_ids.buckets[0] // empty | "\(.key) : \(.doc_count)"' <<<"${logs_response}")"
    if [[ -n "${correlated}" ]]; then
      printf 'OK      logs OTel corrélés (trace_id) avec la trace %s document(s)\n' "${correlated}"
    else
      printf 'KO      aucun log de logs-generic.otel-supermarche_* ne porte le trace_id des traces REST/Kafka\n' >&2
      failures=1
    fi
  fi
fi

if [[ "${mode}" == schema ]]; then
  common_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [{range: {"@timestamp": {gte: ("now-" + $window)}}}],
      should: [
        {bool: {must_not: [{exists: {field: "@timestamp"}}]}},
        {bool: {must_not: [{exists: {field: "data_stream.dataset"}}]}}
      ],
      minimum_should_match: 1
    }}
  }')"
  common_missing="$(count_query 'logs-*,metrics-*,traces-*' "${common_missing_query}")"
  check_zero "documents sans @timestamp ou data_stream.dataset" "${common_missing}"

  trace_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {exists: {field: "span.name"}}
      ],
      should: [
        {bool: {must_not: [{exists: {field: "trace.id"}}]}},
        {bool: {must_not: [{exists: {field: "span.id"}}]}}
      ],
      minimum_should_match: 1
    }}
  }')"
  trace_missing="$(count_query 'traces-*' "${trace_missing_query}")"
  check_zero "spans sans trace.id ou span.id" "${trace_missing}"

  # Le dataset generic d'une plateforme reçoit aussi les logs fichiers de ses
  # VM (filelog, ADR-019) : les contrôles applicatifs se limitent au
  # namespace Kubernetes de l'application.
  service_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {exists: {field: "data_stream.dataset"}},
        {term: {"resource.attributes.k8s.namespace.name": "h0tl-supermarche-app"}}
      ],
      must_not: [{exists: {field: "service.name"}}]
    }}
  }')"
  service_missing="$(count_query 'traces-*,metrics-generic.otel-supermarche_*,logs-generic.otel-supermarche_*' "${service_missing_query}")"
  check_zero "documents OTel applicatifs sans service.name" "${service_missing}"

  # Logs applicatifs OTel natifs (ADR-012) : présents, avec sévérité, corps
  # et identité de service, sans champ ECS hérité du format stdout.
  app_logs_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {filter: [
      {range: {"@timestamp": {gte: ("now-" + $window)}}},
      {term: {"resource.attributes.k8s.namespace.name": "h0tl-supermarche-app"}}
    ]}}
  }')"
  app_logs="$(count_query 'logs-generic.otel-supermarche_*' "${app_logs_query}")"
  if (( app_logs > 0 )); then
    printf 'OK      logs applicatifs OTel natifs : %s document(s)\n' "${app_logs}"
  else
    printf 'KO      aucun log applicatif dans logs-generic.otel-supermarche_*\n' >&2
    failures=1
  fi

  otel_log_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {term: {"resource.attributes.k8s.namespace.name": "h0tl-supermarche-app"}}
      ],
      should: [
        {bool: {must_not: [{exists: {field: "severity_text"}}]}},
        {bool: {must_not: [{exists: {field: "body.text"}}]}},
        {bool: {must_not: [{exists: {field: "resource.attributes.service.name"}}]}}
      ],
      minimum_should_match: 1
    }}
  }')"
  otel_log_missing="$(count_query 'logs-generic.otel-supermarche_*' "${otel_log_missing_query}")"
  check_zero "logs applicatifs sans severity_text, body.text ou service.name" "${otel_log_missing}"

  # Corrélation : un log de niveau INFO ou inférieur (severity_number < 13)
  # est émis par le code applicatif pendant un traitement et porte donc le
  # trace_id de sa trace. Les frameworks n'émettent qu'à partir de WARN
  # (LOGGING_LEVEL_* de architecture/gitops/supermarket/applications.yaml). Seule exception :
  # la ligne de démarrage de la classe principale (*Application), émise
  # avant toute requête.
  untraced_log_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {range: {severity_number: {lt: 13}}},
        {term: {"resource.attributes.k8s.namespace.name": "h0tl-supermarche-app"}}
      ],
      must_not: [
        {exists: {field: "trace_id"}},
        {wildcard: {"scope.name": "*Application"}}
      ]
    }}
  }')"
  untraced_logs="$(count_query 'logs-generic.otel-supermarche_*' "${untraced_log_query}")"
  check_zero "logs applicatifs INFO sans trace_id" "${untraced_logs}"

  # L'UI APM filtre les signaux d'un service par service.environment, alias
  # de resource.attributes.deployment.environment dans les templates OTel
  # d'Elasticsearch. Le collecteur backend le pose depuis le topic (ADR-018).
  no_environment_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {term: {"resource.attributes.k8s.namespace.name": "h0tl-supermarche-app"}}
      ],
      must_not: [{exists: {field: "service.environment"}}]
    }}
  }')"
  no_environment="$(count_query 'logs-generic.otel-supermarche_*,metrics-generic.otel-supermarche_*,traces-generic.otel-supermarche_*' "${no_environment_query}")"
  check_zero "signaux applicatifs sans service.environment (filtre de l'UI APM)" "${no_environment}"

  ecs_log_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [{range: {"@timestamp": {gte: ("now-" + $window)}}}],
      should: [
        {exists: {field: "ecs.version"}},
        {term: {"data_stream.dataset": "supermarche"}}
      ],
      minimum_should_match: 1
    }}
  }')"
  ecs_logs="$(count_query 'logs-supermarche*' "${ecs_log_query}")"
  check_zero "logs applicatifs au format ECS" "${ecs_logs}"
fi

if (( failures )); then
  printf 'Contrôle d’observabilité en échec. Fenêtre contrôlée : %s\n' "${window}" >&2
  exit 1
fi

printf 'Contrôle d’observabilité réussi. Fenêtre contrôlée : %s\n' "${window}"
