#!/usr/bin/env bash
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD hors Git}"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
curl_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:127.0.0.1}"
k8s_namespace="${K8S_NAMESPACE:-elastic-stack}"
kubectl_bin="${KUBECTL:-kubectl}"
kibana_user="${APM_KIBANA_USERNAME:-apm-server-kibana}"
kibana_secret="apm-server-kibana-credentials"
kibana_url="https://elastic-stack-eck-kibana-kb-http.${k8s_namespace}.svc:5601"
kibana_ca_secret="elastic-stack-eck-kibana-kb-http-ca-internal"
kibana_password="${APM_KIBANA_PASSWORD:-}"

if [[ -z "${kibana_password}" ]]; then
  kibana_password="$(openssl rand -base64 32 | tr -d '=+/\n' | cut -c1-32)"
fi

curl_args=(
  --fail --silent --show-error --insecure
  --resolve "${curl_resolve}"
  -u "elastic:${ELASTICSEARCH_PASSWORD}"
  -H 'Content-Type: application/json'
)

curl "${curl_args[@]}" -X PUT "${elasticsearch_url}/_security/user/${kibana_user}" \
  --data "{\"password\":\"${kibana_password}\",\"roles\":[\"viewer\"],\"enabled\":true}" \
  | jq -e '.created == true or .created == false' >/dev/null

ca_file="$(mktemp)"
trap 'rm -f "${ca_file}"' EXIT
"${kubectl_bin}" -n "${k8s_namespace}" get secret "${kibana_ca_secret}" \
  -o jsonpath='{.data.tls\.crt}' | base64 --decode > "${ca_file}"

"${kubectl_bin}" -n "${k8s_namespace}" create secret generic "${kibana_secret}" \
  --from-literal=url="${kibana_url}" \
  --from-literal=username="${kibana_user}" \
  --from-literal=password="${kibana_password}" \
  --from-file=ca.crt="${ca_file}" \
  --dry-run=client -o yaml | "${kubectl_bin}" apply -f - >/dev/null

printf 'Compte Kibana APM en lecture seule et Secret Kubernetes appliqués.\n'
