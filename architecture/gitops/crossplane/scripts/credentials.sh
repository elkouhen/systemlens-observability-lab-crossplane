#!/usr/bin/env bash
# Rend les Secrets de chaque groupe (gitops/<groupe>/secrets/), dérivés de
# .observability-credentials.env (hors Git) : un fichier JSON en clair par Secret dans
# <répertoire>/<groupe>/<nom>.json. Appelé par secrets.sh, qui les chiffre avec SOPS (age).
# Usage : credentials.sh <répertoire>
set -euo pipefail
out=${1:?Usage : credentials.sh <répertoire>}
: "${KAFKA_OTEL_PUBLISHER_PASSWORD:?}" "${KAFKA_OTEL_CONSUMER_PASSWORD:?}" "${POSTGRESQL_PASSWORD:?}" "${ELASTIC_PASSWORD:?}" "${MONGODB_PASSWORD:?}" \
  "${OTEL_EDGE_KEY_KUBERNETES:?}" "${OTEL_EDGE_KEY_KUBERNETES_CLUSTER:?}" "${OTEL_EDGE_KEY_K3S_01:?}" "${OTEL_EDGE_KEY_ELK_01:?}"
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

# Chaîne OTel : provider-kafka (otel-admin, listener externe du Kafka OTel de k3s-01), mot de passe
# de l'administrateur Strimzi, comptes SCRAM, clés Bearer de l'Edge et comptes de supervision des
# collecteurs (recopiés dans k3s-01 par otel-pipeline/target.yaml).
secret otel-pipeline crossplane-system kafka-otel-admin credentials="$(jq -cn --arg p "$(derive otel-admin)" \
  '{brokers: ["192.168.33.50:31092"], sasl: {mechanism: "SCRAM-SHA-512", username: "otel-admin", password: $p}}')"
secret otel-pipeline elastic-stack kafka-otel-admin-password password="$(derive otel-admin)"
secret otel-pipeline crossplane-system kafka-otel-accounts \
  otel_publisher_otel_edge_01="$(derive otel_publisher_otel_edge_01)" \
  otel_consumer="$KAFKA_OTEL_CONSUMER_PASSWORD"
secret otel-pipeline elastic-stack otel-edge-client-keys "${edge_keys[@]}"
secret otel-pipeline elastic-stack otel-collector-credentials kafka-consumer-password="$KAFKA_OTEL_CONSUMER_PASSWORD" \
  kafka-publisher-password="$(derive otel_publisher_otel_edge_01)" \
  postgresql-password="$POSTGRESQL_PASSWORD" mongodb-password="$MONGODB_PASSWORD"
# Clés Bearer acceptées par le Collecteur Edge de k3s-01 (une par ligne, ADR-015) : agents EDOT des
# VM k3s-01 et elk-01, collecteurs Kubernetes (dont les applications).
secret otel-pipeline elastic-stack otel-edge-tokens edge-tokens="$(printf '%s # %s\n' \
  "$OTEL_EDGE_KEY_K3S_01" k3s-01 "$OTEL_EDGE_KEY_ELK_01" elk-01 \
  "$OTEL_EDGE_KEY_KUBERNETES" otel-kubernetes "$OTEL_EDGE_KEY_KUBERNETES_CLUSTER" otel-kubernetes-cluster)"

# Elastic : Terraform, API Kibana, mot de passe elastic lu par les cibles make.
secret elastic crossplane-system elastic-terraform tfvars="$(jq -cn --arg p "$ELASTIC_PASSWORD" '{elastic_password: $p}')"
secret elastic crossplane-system kibana-auth basic="$(printf 'elastic:%s' "$ELASTIC_PASSWORD" | base64 | tr -d '\n')"
secret elastic elastic-stack elasticsearch-es-elastic-user elastic="$ELASTIC_PASSWORD"

# Supermarché : accès du hub aux back-ends de k3s-01 par NodePort (Kafka métier, PostgreSQL en
# superutilisateur postgres, MongoDB avec crossplane_admin, dont le mot de passe est dérivé de
# MONGODB_PASSWORD), comptes des instances (PostgreSQLInstance, MongoDBInstance ; otel_monitor garde
# MONGODB_PASSWORD), Secrets des services.
secret supermarket crossplane-system kafka-business credentials='{"brokers": ["192.168.33.50:31192"]}'
secret supermarket crossplane-system postgresql-admin endpoint=192.168.33.50 port=30432 username=postgres password="$POSTGRESQL_PASSWORD"
secret supermarket crossplane-system postgresql-otel password="$POSTGRESQL_PASSWORD"
secret supermarket crossplane-system mongodb-terraform tfvars="$(jq -cn \
  --arg a "$(printf '%s:%s' "$MONGODB_PASSWORD" crossplane_admin | shasum -a 256 | cut -d' ' -f1)" \
  --arg m "$MONGODB_PASSWORD" '{mongodb_admin_password: $a, otel_monitor_password: $m}')"
secret supermarket h0tl-supermarche-app postgresql-credentials password="$POSTGRESQL_PASSWORD"
secret supermarket h0tl-supermarche-app mongodb-credentials \
  crossplane_admin="$(printf '%s:%s' "$MONGODB_PASSWORD" crossplane_admin | shasum -a 256 | cut -d' ' -f1)" \
  observability="$MONGODB_PASSWORD"
secret supermarket h0tl-supermarche-app otel-edge-client-keys "${edge_keys[@]}"

# demo-api : clé Bearer de l'Edge.
secret demo-api h0tl-demo-app otel-edge-client-keys "${edge_keys[@]}"
