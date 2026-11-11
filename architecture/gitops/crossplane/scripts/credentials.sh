#!/usr/bin/env bash
# Rend les Secrets de chaque groupe (gitops/<groupe>/secrets/), dérivés de
# .observability-credentials.env (hors Git) : un fichier JSON en clair par Secret dans
# <répertoire>/<groupe>/<nom>.json. Appelé par secrets.sh, qui les chiffre avec SOPS (age).
# Usage : credentials.sh <répertoire>
set -euo pipefail
out=${1:?Usage : credentials.sh <répertoire>}
: "${KAFKA_OTEL_PUBLISHER_PASSWORD:?}" "${KAFKA_OTEL_CONSUMER_PASSWORD:?}" "${POSTGRESQL_PASSWORD:?}" "${ELASTIC_PASSWORD:?}" "${MONGODB_PASSWORD:?}" \
  "${OTEL_EDGE_KEY_KUBERNETES:?}" "${OTEL_EDGE_KEY_KUBERNETES_CLUSTER:?}"
KUBECTL=${KUBECTL:-kubectl}

# Même dérivation que le lab (group_vars/all.yml) : sha256("<secret racine>:<compte>")
derive() { printf '%s:%s' "$KAFKA_OTEL_PUBLISHER_PASSWORD" "$1" | shasum -a 256 | cut -d' ' -f1; }

secret() { # groupe, namespace, nom, puis paires clé=valeur
  local group=$1 namespace=$2 name=$3; shift 3
  local args=() kv
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  mkdir -p "$out/$group"
  "$KUBECTL" -n "$namespace" create secret generic "$name" "${args[@]}" --dry-run=client -o json \
    | jq -S 'del(.metadata.creationTimestamp)' > "$out/$group/$name.json"
}
edge_keys=(otel-kubernetes="$OTEL_EDGE_KEY_KUBERNETES" otel-kubernetes-cluster="$OTEL_EDGE_KEY_KUBERNETES_CLUSTER")

# Chaîne OTel : provider-kafka (otel_admin), comptes SCRAM, clés Bearer de l'Edge des collecteurs.
secret otel-pipeline crossplane-system kafka-otel-admin credentials="$(jq -cn --arg p "$(derive otel_admin)" \
  '{brokers: ["192.168.33.20:9092"], sasl: {mechanism: "PLAIN", username: "otel_admin", password: $p}}')"
secret otel-pipeline crossplane-system kafka-otel-accounts \
  otel_publisher_otel_edge_01="$(derive otel_publisher_otel_edge_01)" \
  otel_publisher_otel_backend_01="$(derive otel_publisher_otel_backend_01)" \
  otel_consumer="$KAFKA_OTEL_CONSUMER_PASSWORD"
secret otel-pipeline elastic-stack otel-edge-client-keys "${edge_keys[@]}"

# Elastic : Terraform, API Kibana, mot de passe elastic lu par les cibles make.
secret elastic crossplane-system elastic-terraform tfvars="$(jq -cn --arg p "$ELASTIC_PASSWORD" '{elastic_password: $p}')"
secret elastic crossplane-system kibana-auth basic="$(printf 'elastic:%s' "$ELASTIC_PASSWORD" | base64 | tr -d '\n')"
secret elastic elastic-stack elasticsearch-es-elastic-user elastic="$ELASTIC_PASSWORD"

# Supermarché : Kafka métier, PostgreSQL, MongoDB (compte crossplane_admin amorcé par Ansible, mot de
# passe dérivé de MONGODB_PASSWORD comme mongodb_crossplane_password dans group_vars/all.yml ;
# otel_monitor garde MONGODB_PASSWORD, lu par les agents EDOT), Secrets des services.
secret supermarket crossplane-system kafka-business credentials='{"brokers": ["192.168.33.10:9092"]}'
secret supermarket crossplane-system postgresql-admin endpoint=192.168.33.10 port=5432 username=observability password="$POSTGRESQL_PASSWORD"
secret supermarket crossplane-system postgresql-otel password="$POSTGRESQL_PASSWORD"
secret supermarket crossplane-system mongodb-terraform tfvars="$(jq -cn \
  --arg a "$(printf '%s:%s' "$MONGODB_PASSWORD" crossplane_admin | shasum -a 256 | cut -d' ' -f1)" \
  --arg m "$MONGODB_PASSWORD" '{mongodb_admin_password: $a, otel_monitor_password: $m}')"
secret supermarket h0tl-supermarche-app postgresql-credentials password="$POSTGRESQL_PASSWORD"
secret supermarket h0tl-supermarche-app otel-edge-client-keys "${edge_keys[@]}"

# demo-api : clé Bearer de l'Edge.
secret demo-api h0tl-demo-app otel-edge-client-keys "${edge_keys[@]}"
