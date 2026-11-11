#!/usr/bin/env python3
"""Prépare les Application Crossplane déclarées avec chaque application (kubernetes/apps).

La configuration de l'agent Java OTel reste un fichier versionné (otel/agent.yaml), relu par les
vérifications du lab. Le manifeste d'une Application la désigne par `agentConfigFile`, chemin
relatif au manifeste ; ce script la remplace par son contenu (`agentConfig`), et peut fixer le tag
d'image d'une Application (--tag nom=tag, repris de APP_IMAGE_TAG et DEMO_API_IMAGE_TAG).

Traitement textuel volontaire : aucune dépendance Python hors bibliothèque standard.
Usage : applications.py [--tag nom=tag ...] kubernetes/apps/<app>/application.yaml ... | kubectl apply -f -
"""
import argparse
import os
import re
import sys

AGENT_FILE = re.compile(r"^(?P<indent> *)agentConfigFile: *(?P<path>\S+) *$", re.M)
NAME = re.compile(r"^metadata:\n(?:  .*\n)*?  name: *(?P<name>\S+)", re.M)
TAG = re.compile(r"^(?P<prefix>  image: *\{name: *[^,}]+, *tag: *)(?P<tag>[^}\s]+)(?P<suffix> *\}) *$", re.M)


def render(path, tags):
    base = os.path.dirname(os.path.abspath(path))
    docs = re.split(r"^---[^\n]*\n", open(path, encoding="utf-8").read(), flags=re.M)
    out = []
    for doc in docs:
        if not re.search(r"^kind: *Application *$", doc, re.M):
            continue
        name = NAME.search(doc).group("name")

        def inline(match):
            indent = match.group("indent")
            content = open(os.path.join(base, match.group("path")), encoding="utf-8").read()
            body = "".join(f"{indent}  {line}" if line.strip() else "\n"
                           for line in content.splitlines(keepends=True))
            return f"{indent}agentConfig: |\n{body.rstrip()}"

        doc, count = AGENT_FILE.subn(inline, doc)
        if count != 1:
            sys.exit(f"{path}: {name} doit déclarer exactement un agentConfigFile")
        if name in tags:
            doc, count = TAG.subn(lambda m: m.group("prefix") + tags[name] + m.group("suffix"), doc)
            if count != 1:
                sys.exit(f"{path}: tag d'image introuvable pour {name} (forme attendue : image: {{name: x, tag: y}})")
        # Label d'élagage (scripts/prune.py) : une Application retirée du manifeste est supprimée.
        if re.search(r"(?m)^  labels:", doc):
            sys.exit(f"{path}: {name} : metadata.labels est réservé au label lab.io/managed-by")
        doc = re.sub(r"(?m)^metadata:\n", "metadata:\n  labels: {lab.io/managed-by: applications}\n", doc, count=1)
        out.append(doc.rstrip() + "\n")
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", action="append", default=[], help="nom=tag")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    tags = dict(t.split("=", 1) for t in args.tag)
    docs = [d for f in args.files for d in render(f, tags)]
    for d in docs:
        sys.stdout.write("---\n" + d)
    print(f"{len(docs)} Application générées", file=sys.stderr)


if __name__ == "__main__":
    main()
