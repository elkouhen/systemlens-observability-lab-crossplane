#!/usr/bin/env bash
# À charger, ne pas exécuter : source ./platform/elk/scripts/generate-otel-edge-keys.sh
# Les identifiants restent dans un fichier local ignoré par Git et dans
# l'environnement du shell courant.

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  printf 'Utilisation : source %s\n' "$0" >&2
  exit 1
fi

_observability_credentials_fail() {
  printf 'generate-otel-edge-keys: %s\n' "$1" >&2
  return 1
}

command -v openssl >/dev/null 2>&1 || {
  _observability_credentials_fail 'openssl est requis.'
  return 1
}

# Clés Bearer des clients du collecteur Edge (ADR-015) : une par VM,
# OTEL_EDGE_KEY_<HOST>, plus une par collecteur Kubernetes. Puis les mots de
# passe du lab. Un fichier existant est complété des entrées manquantes.
_observability_credentials_keys=(
  OTEL_EDGE_KEY_KUBERNETES
  OTEL_EDGE_KEY_KUBERNETES_CLUSTER
  OTEL_EDGE_KEY_K3S_01
  OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE_01
  OTEL_EDGE_KEY_ELK_01
  OTEL_EDGE_KEY_OTEL_EDGE_01
  KAFKA_OTEL_PUBLISHER_PASSWORD
  KAFKA_OTEL_CONSUMER_PASSWORD
  POSTGRESQL_PASSWORD
  MONGODB_PASSWORD
  ELASTIC_PASSWORD
)

_observability_credentials_file="${OBSERVABILITY_CREDENTIALS_FILE:-.observability-credentials.env}"
_observability_legacy_file="${OTEL_EDGE_KEYS_FILE:-.otel-edge-keys.env}"

# Migrer automatiquement l'ancien emplacement local s'il existe. Le fichier
# historique est ignoré par Git et peut encore contenir les clés du lab.
if [[ ! -f "${_observability_credentials_file}" && -f "${_observability_legacy_file}" ]]; then
  cp "${_observability_legacy_file}" "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de migrer ${_observability_legacy_file}."
    return 1
  }
  chmod 600 "${_observability_credentials_file}"
fi

if [[ -f "${_observability_credentials_file}" && "${OBSERVABILITY_CREDENTIALS_ROTATE:-${OTEL_EDGE_KEYS_ROTATE:-0}}" != '1' ]]; then
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de charger ${_observability_credentials_file}."
    return 1
  }
else
  _observability_credentials_directory="$(dirname "${_observability_credentials_file}")"
  mkdir -p "${_observability_credentials_directory}" || {
    _observability_credentials_fail "impossible de créer ${_observability_credentials_directory}."
    return 1
  }
  _observability_credentials_tmp="$(mktemp "${_observability_credentials_file}.tmp.XXXXXX")" || {
    _observability_credentials_fail "impossible de créer le fichier temporaire."
    return 1
  }
  umask 077
  {
    for _observability_credentials_key in "${_observability_credentials_keys[@]}"; do
      printf 'export %s=%q\n' "${_observability_credentials_key}" "$(openssl rand -hex 32)"
    done
  } >"${_observability_credentials_tmp}" || {
    rm -f "${_observability_credentials_tmp}"
    _observability_credentials_fail 'impossible d’écrire les identifiants générés.'
    return 1
  }
  chmod 600 "${_observability_credentials_tmp}"
  mv -f "${_observability_credentials_tmp}" "${_observability_credentials_file}" || {
    rm -f "${_observability_credentials_tmp}"
    _observability_credentials_fail "impossible d'installer ${_observability_credentials_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de charger ${_observability_credentials_file}."
    return 1
  }
  printf 'Identifiants d’observabilité générés dans %s.\n' "${_observability_credentials_file}"
fi

# Compléter un fichier existant avec les identifiants ajoutés au périmètre,
# par exemple les clés par VM d'ADR-015. Les valeurs ne sont jamais affichées.
_observability_credentials_missing=()
for _observability_credentials_key in "${_observability_credentials_keys[@]}"; do
  [[ -n "${!_observability_credentials_key:-}" ]] || _observability_credentials_missing+=("${_observability_credentials_key}")
done
if [[ ${#_observability_credentials_missing[@]} -gt 0 ]]; then
  umask 077
  {
    for _observability_credentials_key in "${_observability_credentials_missing[@]}"; do
      printf 'export %s=%q\n' "${_observability_credentials_key}" "$(openssl rand -hex 32)"
    done
  } >>"${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible d'ajouter les identifiants à ${_observability_credentials_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de recharger ${_observability_credentials_file}."
    return 1
  }
  printf 'Identifiants ajoutés à %s : %s.\n' "${_observability_credentials_file}" "${_observability_credentials_missing[*]}"
fi

for _observability_credentials_key in "${_observability_credentials_keys[@]}"; do
  # shellcheck disable=SC2163
  export "${_observability_credentials_key}"
  [[ -n "${!_observability_credentials_key:-}" ]] || {
    _observability_credentials_fail "${_observability_credentials_key} est absente du fichier d’identifiants."
    return 1
  }
done

printf 'Identifiants d’observabilité disponibles dans le shell courant.\n'

unset _observability_credentials_file _observability_legacy_file
unset _observability_credentials_directory _observability_credentials_tmp
unset _observability_credentials_keys _observability_credentials_missing _observability_credentials_key
