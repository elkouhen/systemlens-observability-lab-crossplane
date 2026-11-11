#!/usr/bin/env bash
# Synchronise les pipelines Elasticsearch et les package policies qui doivent
# mettre à jour une policy Fleet déjà existante. Les secrets restent hors du
# dépôt.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/../../../gitops/elastic/assets" && pwd)"
command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }
elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
: "${ELASTICSEARCH_PASSWORD:?Definir ELASTICSEARCH_PASSWORD avant de synchroniser les pipelines}"
kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_password="${KIBANA_PASSWORD:-${ELASTICSEARCH_PASSWORD}}"
elasticsearch_args=(--fail --silent --show-error --insecure
  --resolve elasticsearch.observability.test:9200:127.0.0.1
  -u "elastic:${ELASTICSEARCH_PASSWORD}" -H 'Content-Type: application/json')
kibana_args=(--fail --silent --show-error --insecure
  --resolve "${KIBANA_HOST:-kibana.observability.test}:5601:127.0.0.1"
  -u "elastic:${kibana_password}" -H 'Content-Type: application/json'
  -H 'kbn-xsrf: systemlens-fleet-sync')

# Kafka 3.9 peut publier number-of-voters comme chaîne dans le MBean Raft.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.raft@custom" \
  --data-binary "@${elk_dir}/fleet/kafka-raft-pipeline.json" >/dev/null
printf 'Kafka Raft compatibility pipeline updated\n'

# Les package policies Fleet sont préconfigurées par Kibana dans les manifests
# Kubernetes. Ce script ne gère que les pipelines Elasticsearch @custom qui
# complètent les dashboards, afin de conserver une source de vérité IAC unique.

# Les pipelines @custom sont conserves lors des mises a jour de packages.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.topic@custom" \
  --data-binary "@${elk_dir}/fleet/kafka-topic-ingest-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: metrics-kafka.topic@custom\n'

# L'endpoint Jolokia reste volontairement local à chaque VM. Les métriques
# doivent toutefois identifier le broker qui les a produites, pas localhost.
for dataset in controller jvm network log_manager replica_manager topic raft; do
  pipeline="metrics-kafka.${dataset}@custom"
  existing="$(curl "${elasticsearch_args[@]}" "${elasticsearch_url}/_ingest/pipeline/${pipeline}" 2>/dev/null || printf '{}')"
  payload="$(jq --arg pipeline "${pipeline}" '
    .[$pipeline] // {description: "Kafka custom processors", processors: []}
    # L API GET ajoute ces champs en lecture seule ; ne jamais les renvoyer
    # dans le PUT, sinon Elasticsearch repond 400.
    | del(.created_date_millis, .modified_date_millis)
    | .processors = ([.processors[] | select(.set.tag != "set-kafka-service-address")] +
        [{set: {tag: "set-kafka-service-address", field: "service.address", value: "{{{host.name}}}", override: true}}])
  ' <<<"${existing}")"
  curl "${elasticsearch_args[@]}" -X PUT \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
    --data "${payload}" >/dev/null
done
printf 'Kafka service.address pipelines updated\n'

# Le routage applicatif est exclusivement défini dans le pipeline Logstash
# versionné. Retirer les pipelines Elasticsearch historiques pour qu'aucune
# règle de routage résiduelle ne s'applique après Logstash.
for pipeline in metrics-apm.app@custom logs-kubernetes.container_logs@custom; do
  if curl "${elasticsearch_args[@]}" \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" >/dev/null 2>&1; then
    curl "${elasticsearch_args[@]}" -X DELETE \
      "${elasticsearch_url}/_ingest/pipeline/${pipeline}" >/dev/null
    printf 'Legacy application routing pipeline removed: %s\n' "${pipeline}"
  fi
done

# L'integration MongoDB se connecte volontairement a localhost sur chaque VM.
# Les dashboards groupent toutefois les instances par service.address :
# remplacer uniquement l'adresse locale par le nom de la VM rend les VM
# distinguables, sans reecrire les adresses de replica set deja explicites.
for dataset in collstats dbstats metrics replstatus status; do
  pipeline="metrics-mongodb.${dataset}@custom"
  existing="$(curl "${elasticsearch_args[@]}" "${elasticsearch_url}/_ingest/pipeline/${pipeline}" 2>/dev/null || printf '{}')"
  payload="$(jq --arg pipeline "${pipeline}" '
    .[$pipeline] // {description: "MongoDB custom processors", processors: []}
    | del(.created_date_millis, .modified_date_millis)
    | .processors = ([.processors[] | select(.set.tag != "set-mongodb-local-service-address")] +
        [{set: {
          tag: "set-mongodb-local-service-address",
          field: "service.address",
          value: "{{{host.name}}}",
          if: "ctx.service != null && (ctx.service.address == '\''mongodb://localhost:27017'\'' || ctx.service.address == '\''mongodb://127.0.0.1:27017'\'')",
          override: true
        }}])
  ' <<<"${existing}")"
  curl "${elasticsearch_args[@]}" -X PUT \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
    --data "${payload}" >/dev/null
done
printf 'MongoDB service.address pipelines updated\n'

printf 'Fleet pipelines synchronisés ; aucune policy de collecte classique n’est modifiée.\n'
