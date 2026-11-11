#!/usr/bin/env bash

discover_postgresql_otel_dashboard_ids() {
  local response
  response="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/_find?type=dashboard&search_fields=title&search=postgresql&per_page=100")"
  jq -r '
    .saved_objects[]?
    | select(((.attributes.title // "") | test("postgresql"; "i"))
      and ((.attributes.title // "") | test("otel"; "i")))
    | .id
  ' <<<"${response}"
}

load_postgresql_otel_dashboard_ids() {
  dashboard_ids=()
  while IFS= read -r dashboard_id; do
    dashboard_ids[${#dashboard_ids[@]}]="${dashboard_id}"
  done < <(discover_postgresql_otel_dashboard_ids)
  if (( ${#dashboard_ids[@]} == 0 )); then
    printf 'Aucun dashboard PostgreSQL OTel trouvé dans Kibana\n' >&2
    return 1
  fi
}
