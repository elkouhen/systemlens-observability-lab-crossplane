#!/usr/bin/env bash
# Opérations Fleet ponctuelles (la configuration Fleet elle-même est gérée par Crossplane).
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
kibana_version="${KIBANA_VERSION:-9.5.4}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de configurer Fleet}"

curl_args=(--fail --silent --show-error --insecure --resolve "${kibana_resolve}"
  -u "elastic:${KIBANA_PASSWORD}" -H 'kbn-xsrf: systemlens-fleet-bootstrap'
  -H 'Content-Type: application/json')

# Les packages d'intégration, l'hôte Fleet Server et les agent policies sont déclarés dans
# gitops/elastic/fleet.yaml et réconciliés par Crossplane (make crossplane-fleet-wait).
# Ce script ne garde que les opérations ponctuelles : doublons Fleet Server et clé d'enrôlement.

# Un redémarrage ou une réinitialisation historique du Fleet Server peut
# laisser plusieurs enregistrements actifs pour le même hôte. L'architecture
# La plateforme n'en déploie qu'un seul : conserver celui qui a le dernier check-in et
# retirer uniquement les doublons de la policy Fleet Server.
fleet_server_agents="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/fleet/agents?perPage=1000")"
duplicate_fleet_server_ids="$(jq -r '
  .items
  | map(select(.policy_id == "eck-fleet-server" and .active == true))
  | group_by(.local_metadata.host.hostname)[]
  | sort_by(.last_checkin // "")
  | reverse
  | .[1:]
  | .[].id
' <<<"${fleet_server_agents}")"
while IFS= read -r duplicate_id; do
  [[ -n "${duplicate_id}" ]] || continue
  curl "${curl_args[@]}" -X POST \
    "${kibana_url}/api/fleet/agents/${duplicate_id}/unenroll" >/dev/null
  curl "${curl_args[@]}" -X DELETE \
    "${kibana_url}/api/fleet/agents/${duplicate_id}" >/dev/null
  printf 'Ancien Fleet Server supprimé : %s\n' "${duplicate_id}"
done <<<"${duplicate_fleet_server_ids}"

# Fleet Server reste en attente tant que sa policy ne possède pas au moins une
# clé d'enrôlement active. Créer cette clé une seule fois permet à Fleet Server de
# démarrer correctement après une réinstallation ou une nouvelle VM.
fleet_server_enrollment_keys="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/fleet/enrollment_api_keys?perPage=1000" |
  jq '[.items[] | select(.policy_id == "eck-fleet-server" and .active == true)] | length')"
if [[ "${fleet_server_enrollment_keys}" == '0' ]]; then
  curl "${curl_args[@]}" -X POST "${kibana_url}/api/fleet/enrollment_api_keys" \
    --data '{"name":"systemlens-fleet-server-bootstrap","policy_id":"eck-fleet-server"}' >/dev/null
fi

printf 'Packages Fleet installés pour les assets et le monitoring OpAMP ; aucune collecte Fleet classique n’est configurée.\n'
