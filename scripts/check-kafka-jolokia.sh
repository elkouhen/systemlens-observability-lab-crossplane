#!/usr/bin/env bash
# Vérifie que Jolokia expose les MBeans requis par l'intégration Kafka Fleet.
set -uo pipefail

base_url="http://127.0.0.1:8778/jolokia"

usage() {
  cat <<'EOF'
Usage: check-kafka-jolokia.sh [--url URL]

Teste l'API Jolokia et les MBeans nécessaires aux streams Kafka Fleet.

Exemples :
  # Depuis la VM supermarket-middleware-01
  ./scripts/check-kafka-jolokia.sh

  # Depuis l'hôte, via une redirection de port Lima
  ./scripts/check-kafka-jolokia.sh --url http://127.0.0.1:18781/jolokia
EOF
}

while (($#)); do
  case "$1" in
    -u|--url)
      [[ $# -ge 2 ]] || { printf 'Option %s sans URL\n' "$1" >&2; exit 2; }
      base_url="${2%/}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Option inconnue : %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }

request() {
  curl --fail --silent --show-error --globoff --connect-timeout 5 --max-time 15 "$1"
}

failures=0
printf 'Jolokia : %s\n\n' "$base_url"

if version=$(request "$base_url/version"); then
  if jq -e '.status == 200' >/dev/null <<<"$version"; then
    printf 'OK   API Jolokia accessible (%s)\n' "$(jq -r '.value.agent_version // "version inconnue"' <<<"$version")"
  else
    printf 'KO   API Jolokia : réponse inattendue\n' >&2
    failures=$((failures + 1))
  fi
else
  printf 'KO   API Jolokia inaccessible\n' >&2
  exit 1
fi

printf '\n%-18s %8s  %s\n' 'Stream Fleet' 'MBeans' 'Motif Jolokia'
printf '%-18s %8s  %s\n' '------------------' '--------' '--------------'

streams=(
  'kafka.controller|kafka.controller:*'
  'kafka.jvm|java.lang:*'
  'kafka.network|kafka.network:*'
  'kafka.log_manager|kafka.log:*'
  'kafka.replica_manager|kafka.server:type=ReplicaManager,*'
  'kafka.topic|kafka.server:type=BrokerTopicMetrics,*'
  'kafka.raft|kafka.server:type=raft-metrics,*'
)

for stream in "${streams[@]}"; do
  name=${stream%%|*}
  pattern=${stream#*|}

  if response=$(request "$base_url/search/$pattern"); then
    count=$(jq -r 'if .status == 200 and (.value | type) == "array" then (.value | length) else -1 end' <<<"$response")
    if [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
      printf 'OK   %-15s %8d  %s\n' "$name" "$count" "$pattern"
    else
      printf 'KO   %-15s %8s  %s\n' "$name" "${count/-1/?}" "$pattern" >&2
      failures=$((failures + 1))
    fi
  else
    printf 'KO   %-15s %8s  %s\n' "$name" '?' "$pattern" >&2
    failures=$((failures + 1))
  fi
done

if ((failures)); then
  printf '\n%d contrôle(s) en échec.\n' "$failures" >&2
  exit 1
fi

printf '\nTous les streams Kafka configurés ont au moins un MBean exposé.\n'
