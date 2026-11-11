#!/usr/bin/env bash
# À charger, ne pas exécuter : source ./platform/elk/scripts/load-credentials.sh
# Les secrets restent uniquement dans l'environnement du shell courant.

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  printf 'Utilisation : source %s\n' "$0" >&2
  exit 1
fi

_credentials_fail() {
  printf 'load-credentials: %s\n' "$1" >&2
  return 1
}

command -v kubectl >/dev/null 2>&1 || {
  _credentials_fail 'kubectl est requis.'
  return 1
}
command -v curl >/dev/null 2>&1 || {
  _credentials_fail 'curl est requis.'
  return 1
}
command -v jq >/dev/null 2>&1 || {
  _credentials_fail 'jq est requis.'
  return 1
}

export ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
export KIBANA_URL="${KIBANA_URL:-http://kibana.observability.test:5601}"
_credentials_namespace="${ELASTIC_NAMESPACE:-elastic-stack}"
_credentials_app_namespace="${APP_NAMESPACE:-h0tl-supermarche-app}"
_credentials_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"

# Le Secret applicatif est la source persistante du mot de passe PostgreSQL.
# Une valeur déjà fournie par un coffre-fort reste prioritaire ; le Secret est
# utilisé pour permettre à `source` puis `make deploy` de fonctionner sans
# recopier le mot de passe dans le shell.
if [[ -z "${POSTGRESQL_PASSWORD:-}" ]]; then
  _postgresql_password_from_secret="$(kubectl -n "${_credentials_app_namespace}" get secret postgresql-credentials \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || true)"
  if [[ -n "${_postgresql_password_from_secret}" ]]; then
    export POSTGRESQL_PASSWORD="${_postgresql_password_from_secret}"
  fi
  unset _postgresql_password_from_secret
fi

if ! kubectl -n "${_credentials_namespace}" get secret elasticsearch-es-elastic-user >/dev/null 2>&1; then
  printf 'load-credentials: secrets ELK absents, ils seront créés par make deploy.\n' >&2
  unset _credentials_namespace _credentials_app_namespace _credentials_resolve
  return 0
fi

ELASTICSEARCH_PASSWORD="$(kubectl -n "${_credentials_namespace}" get secret elasticsearch-es-elastic-user \
  -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode || true)"
if [[ -z "${ELASTICSEARCH_PASSWORD}" ]]; then
  _credentials_fail 'le secret elasticsearch-es-elastic-user ne contient pas de mot de passe.'
  return 1
fi
export ELASTICSEARCH_PASSWORD
export KIBANA_PASSWORD="${ELASTICSEARCH_PASSWORD}"
export ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-${ELASTICSEARCH_PASSWORD}}"

# Une clé déjà chargée est vérifiée contre le cluster courant. Après une
# recréation Elasticsearch, une ancienne clé peut être invalide : elle doit
# alors être remplacée automatiquement avant le provisionnement des VM.
api_key_status=''
if [[ -n "${ELASTICSEARCH_API_KEY:-}" ]]; then
  api_key_status="$(curl --silent --show-error --insecure \
    --resolve "${_credentials_resolve}" \
    -H "Authorization: ApiKey ${ELASTICSEARCH_API_KEY}" \
    -o /dev/null -w '%{http_code}' \
    "${ELASTICSEARCH_URL}/_security/_authenticate" || true)"
fi
if [[ "${api_key_status}" != 200 ]]; then
  _credentials_payload='{"name":"vm-beats-shell","role_descriptors":{"vm_beats_writer":{"cluster":["monitor","read_ilm","manage_ilm","manage_index_templates"],"indices":[{"names":["logs-*","metrics-*","filebeat-*","metricbeat-*"],"privileges":["auto_configure","create_doc","view_index_metadata"]}]}}}'
  ELASTICSEARCH_API_KEY="$(curl --fail --silent --show-error --insecure \
    --resolve "${_credentials_resolve}" \
    -u "elastic:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${ELASTICSEARCH_URL}/_security/api_key" \
    --data "${_credentials_payload}" | jq -er '.id + ":" + .api_key')" || {
      _credentials_fail 'impossible de créer la clé API Elasticsearch.'
      return 1
    }
  export ELASTICSEARCH_API_KEY
fi

printf 'Identifiants chargés : ELASTICSEARCH_PASSWORD, KIBANA_PASSWORD, ELASTICSEARCH_API_KEY, POSTGRESQL_PASSWORD.\n'
unset _credentials_namespace _credentials_app_namespace _credentials_resolve _credentials_payload api_key_status
