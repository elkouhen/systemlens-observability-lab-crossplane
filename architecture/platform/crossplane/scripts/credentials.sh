#!/usr/bin/env bash
# Rend les Secrets d'accès aux back-ends (crossplane-system), dérivés de
# .observability-credentials.env (hors Git), un fichier JSON en clair par Secret dans <répertoire>.
# Appelé par secrets.sh, qui les chiffre avec SOPS (age) dans platform/crossplane/secrets/.
# Usage : credentials.sh <répertoire>
set -euo pipefail
out=${1:?Usage : credentials.sh <répertoire>}
: "${KAFKA_OTEL_PUBLISHER_PASSWORD:?}" "${KAFKA_OTEL_CONSUMER_PASSWORD:?}" "${POSTGRESQL_PASSWORD:?}" "${ELASTIC_PASSWORD:?}" "${MONGODB_PASSWORD:?}" \
  "${OTEL_EDGE_KEY_KUBERNETES:?}" "${OTEL_EDGE_KEY_KUBERNETES_CLUSTER:?}"
KUBECTL=${KUBECTL:-kubectl}

# Même dérivation que le lab (group_vars/all.yml) : sha256("<secret racine>:<compte>")
derive() { printf '%s:%s' "$KAFKA_OTEL_PUBLISHER_PASSWORD" "$1" | shasum -a 256 | cut -d' ' -f1; }

apply_secret() { # nom, puis paires clé=valeur
  local name=$1; shift
  local args=() kv
  for kv in "$@"; do args+=(--from-literal="$kv"); done
  "$KUBECTL" -n crossplane-system create secret generic "$name" "${args[@]}" --dry-run=client -o json \
    | jq -S 'del(.metadata.creationTimestamp)' > "$out/$name.json"
}

apply_secret kafka-otel-admin credentials="$(jq -cn --arg p "$(derive otel_admin)" \
  '{brokers: ["192.168.33.20:9092"], sasl: {mechanism: "PLAIN", username: "otel_admin", password: $p}}')"
apply_secret kafka-business credentials='{"brokers": ["192.168.33.10:9092"]}'
apply_secret kafka-otel-accounts \
  otel_publisher_otel_edge_01="$(derive otel_publisher_otel_edge_01)" \
  otel_publisher_otel_backend_01="$(derive otel_publisher_otel_backend_01)" \
  otel_consumer="$KAFKA_OTEL_CONSUMER_PASSWORD"
apply_secret postgresql-admin endpoint=192.168.33.10 port=5432 username=observability password="$POSTGRESQL_PASSWORD"
apply_secret postgresql-otel password="$POSTGRESQL_PASSWORD"
apply_secret elastic-terraform tfvars="$(jq -cn --arg p "$ELASTIC_PASSWORD" '{elastic_password: $p}')"
apply_secret kibana-auth basic="$(printf 'elastic:%s' "$ELASTIC_PASSWORD" | base64 | tr -d '\n')"
# MongoDB : compte crossplane_admin amorcé par Ansible (mot de passe dérivé de MONGODB_PASSWORD,
# comme mongodb_crossplane_password dans group_vars/all.yml) ; otel_monitor garde MONGODB_PASSWORD,
# lu par les agents EDOT.
apply_secret mongodb-terraform tfvars="$(jq -cn \
  --arg a "$(printf '%s:%s' "$MONGODB_PASSWORD" crossplane_admin | shasum -a 256 | cut -d' ' -f1)" \
  --arg m "$MONGODB_PASSWORD" '{mongodb_admin_password: $a, otel_monitor_password: $m}')"
# Source unique des Secrets des workloads de k3s-01 : provider-kubernetes en copie les valeurs dans
# les namespaces applicatifs (platform/crossplane/kubernetes/secrets.yaml).
apply_secret lab-secrets \
  otel-kubernetes="$OTEL_EDGE_KEY_KUBERNETES" \
  otel-kubernetes-cluster="$OTEL_EDGE_KEY_KUBERNETES_CLUSTER" \
  postgresql-password="$POSTGRESQL_PASSWORD" \
  elastic-password="$ELASTIC_PASSWORD"
