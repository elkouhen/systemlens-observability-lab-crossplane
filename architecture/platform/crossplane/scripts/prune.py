#!/usr/bin/env python3
"""Supprime les ressources Crossplane générées qui ont disparu de leur source.

Les Object (scripts/kubernetes-objects.py) et les Application (scripts/applications.py) portent le
label lab.io/managed-by. Après leur application, ce script compare, namespace par namespace, les
ressources présentes dans le cluster avec ce label et celles du rendu : les ressources absentes du
rendu sont supprimées, ce qui supprime aussi l'objet Kubernetes qu'elles gèrent. Seuls les
namespaces présents dans le rendu sont examinés : appliquer une seule application n'élague pas les
autres.

Usage : prune.py <ressource> <valeur du label lab.io/managed-by> <rendu.yaml>
"""
import os
import re
import subprocess
import sys


def rendered(path):
    found = {}
    for doc in re.split(r"(?m)^---[^\n]*\n", open(path, encoding="utf-8").read()):
        meta = re.search(r"(?m)^metadata:\n((?:  .*\n)+)", doc)
        if not meta:
            continue
        name = re.search(r"(?m)^  name: *(\S+)", meta.group(1))
        namespace = re.search(r"(?m)^  namespace: *(\S+)", meta.group(1))
        if name and namespace:
            found.setdefault(namespace.group(1), set()).add(name.group(1))
    return found


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    resource, value, path = sys.argv[1:]
    kubectl = os.environ.get("KUBECTL", "kubectl")
    for namespace, keep in sorted(rendered(path).items()):
        existing = subprocess.run(
            [kubectl, "-n", namespace, "get", resource, "-l", f"lab.io/managed-by={value}",
             "-o", "jsonpath={.items[*].metadata.name}"],
            check=True, capture_output=True, text=True).stdout.split()
        for name in sorted(set(existing) - keep):
            print(f"Élagage : {resource} {namespace}/{name} (absent de la source)", file=sys.stderr)
            subprocess.run([kubectl, "-n", namespace, "delete", resource, name, "--wait=false"], check=True)


if __name__ == "__main__":
    main()
