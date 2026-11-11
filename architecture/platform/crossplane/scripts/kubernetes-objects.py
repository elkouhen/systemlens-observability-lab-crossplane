#!/usr/bin/env python3
"""Enveloppe chaque objet rendu par Kustomize dans un Object provider-kubernetes.

Les manifests Kustomize de platform/kubernetes restent la source : ce script lance
`kubectl kustomize <répertoire>` et produit un Object par objet rendu (namespace, Services et
EndpointSlices vers les VM, IngressRoutes, collecteurs OTel, RBAC). Crossplane les crée et les
réaligne en continu (watch) ; un objet modifié à la main revient à sa définition.

Le Namespace n'est jamais supprimé par Crossplane (pas de politique Delete) : il porte aussi des
ressources hors de cette couche (Workspace elasticsearch, Secrets, ConfigMap elastic-assets).

Traitement textuel de la sortie normalisée de Kustomize : aucune dépendance hors bibliothèque
standard. Usage : kubernetes-objects.py <répertoire kustomize> | kubectl apply -f -
"""
import os
import re
import subprocess
import sys

LABEL = "kubernetes-objects"
NO_DELETE = ["Observe", "Create", "Update", "LateInitialize"]


def field(doc, pattern):
    match = re.search(pattern, doc, re.M)
    return match.group(1) if match else None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    kubectl = os.environ.get("KUBECTL", "kubectl")
    rendered = subprocess.run([kubectl, "kustomize", sys.argv[1]], check=True,
                              capture_output=True, text=True).stdout
    count = 0
    for doc in re.split(r"^---\n", rendered, flags=re.M):
        if not doc.strip():
            continue
        kind = field(doc, r"^kind: (\S+)$")
        meta = field(doc, r"^metadata:\n((?:  .*\n)+)")
        name = field(meta, r"^  name: (\S+)$")
        namespace = field(meta, r"^  namespace: (\S+)$")
        object_name = "-".join(p for p in ("platform", kind.lower(), namespace, name) if p)
        manifest = "".join("      " + line if line.strip() else "\n"
                           for line in doc.rstrip().splitlines(keepends=True))
        policies = f"\n  managementPolicies: {NO_DELETE}".replace("'", '"') if kind == "Namespace" else ""
        sys.stdout.write(
            "---\n"
            "apiVersion: kubernetes.m.crossplane.io/v1alpha1\n"
            "kind: Object\n"
            "metadata:\n"
            f"  name: {object_name}\n"
            "  namespace: crossplane-system\n"
            f"  labels: {{lab.io/managed-by: {LABEL}}}\n"
            "spec:\n"
            "  providerConfigRef: {kind: ClusterProviderConfig, name: kubernetes}\n"
            f"  watch: true{policies}\n"
            "  forProvider:\n"
            "    manifest:\n"
            f"{manifest.rstrip()}\n"
        )
        count += 1
    print(f"{count} Object générés depuis {sys.argv[1]}", file=sys.stderr)


if __name__ == "__main__":
    main()
