#!/usr/bin/env bash
# Secrets de chaque groupe, versionnés chiffrés par SOPS (age) dans gitops/<groupe>/secrets/ et
# déchiffrés par le plugin ksops d'Argo CD.
#   secrets.sh encrypt : rend les Secrets depuis .observability-credentials.env (credentials.sh) et
#                        rechiffre uniquement ceux dont la valeur a changé (pas de diff Git inutile) ;
#                        tient à jour la liste des fichiers du générateur KSOPS de chaque groupe.
#   secrets.sh check   : échoue si un Secret chiffré ne correspond plus aux identifiants locaux.
# Les variables de .observability-credentials.env doivent être chargées ; le chiffrement n'a besoin
# que de la clé publique (.sops.yaml), le déchiffrement de la clé privée age (SOPS_AGE_KEY_FILE).
set -euo pipefail
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
mode=${1:?Usage : secrets.sh encrypt|check}
here="$(cd "$(dirname "$0")" && pwd)"
gitops="$(cd "$here/../.." && pwd)"
repo="$(cd "$gitops/../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$here/credentials.sh" "$tmp"

changed=0
for groupdir in "$tmp"/*/; do
  group=$(basename "$groupdir")
  dir="$gitops/$group/secrets"
  mkdir -p "$dir"
  for plain in "$groupdir"*.json; do
    name=$(basename "$plain" .json)
    target="$dir/$name.sops.yaml"
    if [ -f "$target" ] && sops decrypt --output-type json "$target" 2>/dev/null | jq -S . | cmp -s - "$plain"; then continue; fi
    changed=$((changed + 1))
    if [ "$mode" = check ]; then echo "Secret $group/$name : différent des identifiants locaux" >&2; continue; fi
    (cd "$repo" && sops encrypt --filename-override "${target#"$repo"/}" --input-type json --output-type yaml "$plain") > "$target.tmp"
    mv "$target.tmp" "$target"
    echo "Secret $group/$name chiffré"
  done
  # Générateur KSOPS du groupe : tous les fichiers chiffrés de secrets/.
  generator="$dir/secret-generator.yaml"
  expected="$(cat <<GEN
# Secrets du groupe $group, chiffrés par SOPS (age) ; liste tenue à jour par make secrets-encrypt.
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: $group-secrets
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ksops
files:
$(cd "$dir" && ls *.sops.yaml | sed 's|^|  - |')
GEN
)"
  if [ "$expected" != "$(cat "$generator" 2>/dev/null)" ]; then
    if [ "$mode" = check ]; then echo "$group/secrets/secret-generator.yaml ne liste pas tous les Secrets chiffrés" >&2; changed=$((changed + 1))
    else printf '%s\n' "$expected" > "$generator"; echo "Générateur $group/secrets/secret-generator.yaml mis à jour"; fi
  fi
done
if [ "$mode" = check ] && [ "$changed" -ne 0 ]; then
  echo "Lancer make secrets-encrypt, puis committer et pousser gitops/*/secrets/." >&2; exit 1
fi
echo "Secrets SOPS à jour ($changed modifié(s))"
