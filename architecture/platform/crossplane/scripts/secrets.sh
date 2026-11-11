#!/usr/bin/env bash
# Secrets d'accès des providers Crossplane, versionnés chiffrés par SOPS (age) dans
# platform/crossplane/secrets/ et déchiffrés par KSOPS dans Argo CD (Application crossplane-secrets).
#   secrets.sh encrypt : rend les Secrets depuis .observability-credentials.env (credentials.sh) et
#                        rechiffre uniquement ceux dont la valeur a changé (pas de diff Git inutile).
#   secrets.sh check   : échoue si un Secret chiffré ne correspond plus aux identifiants locaux.
# Les variables de .observability-credentials.env doivent être chargées ; le chiffrement n'a besoin
# que de la clé publique (.sops.yaml), le déchiffrement de la clé privée age (SOPS_AGE_KEY_FILE).
set -euo pipefail
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
mode=${1:?Usage : secrets.sh encrypt|check}
here="$(cd "$(dirname "$0")" && pwd)"
dir="$(cd "$here/../secrets" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$here/credentials.sh" "$tmp"

changed=0
for plain in "$tmp"/*.json; do
  name=$(basename "$plain" .json)
  target="$dir/$name.sops.yaml"
  if [ -f "$target" ] && sops decrypt --output-type json "$target" 2>/dev/null | jq -S . | cmp -s - "$plain"; then continue; fi
  changed=$((changed + 1))
  if [ "$mode" = check ]; then echo "Secret $name : différent des identifiants locaux" >&2; continue; fi
  (cd "$repo" && sops encrypt --filename-override "${target#"$repo"/}" --input-type json --output-type yaml "$plain") > "$target.tmp"
  mv "$target.tmp" "$target"
  echo "Secret $name chiffré"
done
# Le générateur KSOPS liste tous les fichiers chiffrés.
files=$(cd "$dir" && ls *.sops.yaml | sed 's/^/  - /')
expected=$(sed '/^files:$/q' "$dir/secret-generator.yaml"; printf '%s\n' "$files")
if [ "$expected" != "$(cat "$dir/secret-generator.yaml")" ]; then
  if [ "$mode" = check ]; then echo "secret-generator.yaml ne liste pas tous les Secrets chiffrés" >&2; changed=1
  else printf '%s\n' "$expected" > "$dir/secret-generator.yaml"; fi
fi
if [ "$mode" = check ] && [ "$changed" -ne 0 ]; then
  echo "Lancer make secrets-encrypt, puis committer et pousser platform/crossplane/secrets/." >&2; exit 1
fi
echo "Secrets SOPS à jour ($changed modifié(s))"
