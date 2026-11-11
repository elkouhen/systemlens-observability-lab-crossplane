#!/usr/bin/env bash
# Publie les fichiers JSON/NDJSON versionnés de platform/elk dans le ConfigMap elastic-assets,
# lu par les Workspaces Terraform (varFiles). Les fichiers restent la source de vérité.
set -euo pipefail
KUBECTL=${KUBECTL:-kubectl}
ELK="$(cd "$(dirname "$0")/../../elk" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
jq -n --slurpfile r "$ELK/ilm/retention.json" \
      --slurpfile raft "$ELK/fleet/kafka-raft-pipeline.json" \
      --slurpfile topic "$ELK/fleet/kafka-topic-ingest-pipeline.json" \
  '{retention: $r[0], kafka_raft_pipeline: $raft[0], kafka_topic_pipeline: $topic[0]}' > "$tmp/elasticsearch.tfvars.json"
jq -n --rawfile apm "$ELK/dashboards/apm-data-view.ndjson" \
  '{saved_objects: {"apm-data-view": $apm}}' > "$tmp/kibana.tfvars.json"
# Règles d'alerte seulement : le tableau slos du même fichier n'est plus déployé.
jq '{rules: .rules}' "$ELK/alerts/observability-policies.json" > "$tmp/kibana-alerting.tfvars.json"
for ns in elastic-stack crossplane-system; do
  "$KUBECTL" -n "$ns" create configmap elastic-assets \
    --from-file="$tmp/elasticsearch.tfvars.json" --from-file="$tmp/kibana.tfvars.json" \
    --from-file="$tmp/kibana-alerting.tfvars.json" \
    --dry-run=client -o yaml | "$KUBECTL" apply -f - >/dev/null
  echo "ConfigMap $ns/elastic-assets"
done
