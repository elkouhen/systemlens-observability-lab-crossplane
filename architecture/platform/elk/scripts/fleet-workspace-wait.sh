#!/usr/bin/env bash
# Attend le Workspace Terraform « fleet » (gitops/elastic/fleet.yaml) et répare le seul blocage
# connu : une agent policy créée par Fleet alors que Terraform a perdu la réponse (Kibana
# momentanément indisponible pendant l'apply). Terraform la recrée alors en boucle et reçoit
# « HTTP 409 Agent Policy '<id>' already exists ». Une policy orpheline sans agent est supprimée
# pour que Terraform la recrée et l'enregistre dans son état ; une policy qui a des agents n'est
# jamais supprimée.
set -euo pipefail

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD}"
kubectl_bin="${KUBECTL:-kubectl}"
kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:127.0.0.1}"
timeout_seconds="${FLEET_WORKSPACE_TIMEOUT:-1800}"
curl_args=(--fail --silent --show-error --resolve "${kibana_resolve}" -u "elastic:${KIBANA_PASSWORD}"
  -H 'kbn-xsrf: systemlens-fleet-workspace' -H 'Content-Type: application/json')

deadline=$(( $(date +%s) + timeout_seconds ))
last_delete=0
while (( $(date +%s) < deadline )); do
  conditions="$("${kubectl_bin}" -n crossplane-system get workspaces.tf.m.upbound.io fleet \
    -o jsonpath='{.status.conditions}' 2>/dev/null || true)"
  if jq -e 'any(.[]?; .type == "Ready" and .status == "True")' <<<"${conditions:-[]}" >/dev/null 2>&1; then
    echo 'Workspace Terraform fleet prêt'
    exit 0
  fi
  message="$(jq -r '.[]? | select(.type == "Synced") | .message // empty' <<<"${conditions:-[]}" 2>/dev/null || true)"
  if [[ "${message}" == *"HTTP 409"* ]]; then
    log="$(sed -n 's/.*To see the full error run: echo "\([^"]*\)".*/\1/p' <<<"${message}" | base64 --decode 2>/dev/null | gunzip 2>/dev/null || true)"
    policy_id="$(tr '\n' ' ' <<<"${log}" | sed -n "s/.*Agent Policy '\([^']*\)' *already exists.*/\1/p")"
    # Le message du Workspace reste celui du dernier apply : laisser à Terraform 5 minutes pour
    # recréer la policy après une suppression, et ne supprimer qu'une policy existante.
    if [[ -n "${policy_id}" ]] && (( $(date +%s) - last_delete > 300 )) && curl "${curl_args[@]}" -o /dev/null "${kibana_url}/api/fleet/agent_policies/${policy_id}" 2>/dev/null; then
      agents="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/agents?perPage=1&kuery=policy_id:%22${policy_id}%22" | jq -r '.total // 0')"
      if [[ "${agents}" == 0 ]]; then
        curl "${curl_args[@]}" -X POST "${kibana_url}/api/fleet/agent_policies/delete" \
          --data "{\"agentPolicyId\":\"${policy_id}\"}" >/dev/null
        last_delete="$(date +%s)"
        echo "Policy Fleet orpheline ${policy_id} supprimée : Terraform la recrée"
      else
        echo "Policy Fleet ${policy_id} en conflit mais utilisée par ${agents} agent(s) : intervention requise" >&2
        exit 1
      fi
    fi
  fi
  sleep 20
done
echo "Workspace Terraform fleet non prêt après ${timeout_seconds} s" >&2
exit 1
