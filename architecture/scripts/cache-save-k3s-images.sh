#!/usr/bin/env bash
# Exécuté en root dans chaque VM k3s (make cache-save-k3s-images) : sauvegarde chaque image de
# containerd (k8s.io) dans le cache local de l'hôte, une archive par image et un répertoire par VM,
# sous un nom temporaire renommé
# ensuite. Le rôle Ansible k3s les fait importer par k3s au premier démarrage d'une VM neuve.
# Une image déjà en cache n'est pas réexportée. Certaines images (index multi-plateformes dont une
# partie manque) sont complétées par content fetch ; celles qui restent non exportables sont
# signalées et ignorées, k3s les retéléchargera.
set -euo pipefail

cache=/var/cache/lab/k3s/$(hostname)
k3s=/usr/local/bin/k3s
mountpoint -q /var/cache/lab || { echo "Cache local non monté sur $(hostname) : rien à sauvegarder"; exit 0; }
mkdir -p "$cache"
# ctr export écrit ses archives de façon non séquentielle : écrites directement dans le montage
# virtiofs, une partie sortait tronquée. L'export se fait donc sur le disque de la VM, l'archive est
# contrôlée (tar), puis copiée dans le cache sous un nom temporaire renommé ensuite.
work=$(mktemp -d /var/tmp/lab-images.XXXXXX)
trap 'rm -rf "$work"' EXIT

# Archive complète : lisible par tar et contenant index.json, manifest.json et oci-layout, écrits
# en dernier par ctr export (une archive tronquée peut rester lisible par tar).
valid() { [ "$(tar -tf "$1" 2>/dev/null | grep -cxE 'index.json|manifest.json|oci-layout')" = 3 ]; }

saved=0 present=0 skipped=0 replaced=0
while read -r ref; do
  name="lab-$(printf '%s' "$ref" | tr '/:@' '___').tar"
  archive="$cache/$name"
  if [ -s "$archive" ]; then
    if valid "$archive"; then present=$((present + 1)); continue; fi
    rm -f "$archive"; replaced=$((replaced + 1))
  fi
  local_tar="$work/$name"
  platform="linux/$(dpkg --print-architecture)"
  # Certains index (paquets Crossplane) référencent un petit blob que containerd n'a pas gardé :
  # content fetch le récupère (quelques centaines d'octets) avant un second essai.
  if { "$k3s" ctr -n k8s.io images export --platform "$platform" "$local_tar" "$ref" 2>/dev/null \
       || { "$k3s" ctr -n k8s.io content fetch --platform "$platform" "$ref" >/dev/null 2>&1 \
            && "$k3s" ctr -n k8s.io images export --platform "$platform" "$local_tar" "$ref" 2>/dev/null; }; } \
     && valid "$local_tar"; then
    tmp="$archive.$$.tmp"
    cp "$local_tar" "$tmp" && mv -f "$tmp" "$archive"; saved=$((saved + 1))
  else
    skipped=$((skipped + 1)); echo "Image non exportable, ignorée : $ref"
  fi
  rm -f "$local_tar"
done < <("$k3s" ctr -n k8s.io images ls -q | grep -v -e '^sha256:' -e '@sha256:' | sort)

echo "Images de $(hostname) : $saved sauvegardée(s) dont $replaced archive(s) invalide(s) remplacée(s), $present déjà en cache, $skipped ignorée(s)"
