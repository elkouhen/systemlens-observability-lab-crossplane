#!/usr/bin/env python3
"""Génère les ressources provider-http (Request) des dashboards Kibana décrits en JSON brut.

Source inchangée du lab : platform/elk/dashboards/*.json avec "panels", poussés par l'API
Dashboards (PUT /api/dashboards/<id>). Les dashboards restent en provider-http :
elasticstack_kibana_dashboard imposerait de réécrire les panneaux ES|QL dans son propre schéma.
Les règles d'alerte sont gérées par Terraform (elastic/kibana-alerting.yaml) ; les SLO ne sont
plus déployés.

Chaque Request est réconciliée par Crossplane : création si absente (404), mise à jour quand
l'objet observé ne correspond plus au JSON versionné, suppression avec la ressource.
Usage : kibana-requests.py | kubectl apply -f -
"""
import glob
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "elk"))
KIBANA = os.environ.get("KIBANA_INTERNAL_URL", "http://192.168.33.40:5601")
AUTH = "Basic {{ kibana-auth:crossplane-system:basic }}"


def headers(extra=None):
    h = {
        "Content-Type": ["application/json"],
        "kbn-xsrf": ["crossplane"],
        "Authorization": [AUTH],
    }
    h.update(extra or {})
    return h


def request(name, url, body, mappings, check, hdrs=None):
    return {
        "apiVersion": "http.m.crossplane.io/v1alpha2",
        "kind": "Request",
        "metadata": {"name": name, "namespace": "crossplane-system",
                     "labels": {"lab.io/managed-by": "kibana-requests"}},
        "spec": {
            "providerConfigRef": {"kind": "ClusterProviderConfig", "name": "kibana"},
            "forProvider": {
                "waitTimeout": "2m",
                "headers": headers(hdrs),
                "payload": {"baseUrl": url, "body": json.dumps(body, ensure_ascii=False)},
                "mappings": mappings,
                "expectedResponseCheck": {"type": "CUSTOM", "logic": check},
                "isRemovedCheck": {"type": "CUSTOM", "logic": ".response.statusCode == 404"},
            },
        },
    }


def dashboards():
    for path in sorted(glob.glob(os.path.join(ROOT, "dashboards", "*.json"))):
        doc = json.load(open(path))
        if not isinstance(doc.get("panels"), list):
            continue
        dash_id = doc.pop("id")
        yield request(
            f"dashboard-{dash_id}",
            f"{KIBANA}/api/dashboards/{dash_id}",
            doc,
            [
                {"action": "CREATE", "method": "PUT", "url": ".payload.baseUrl", "body": ".payload.body"},
                {"action": "OBSERVE", "method": "GET", "url": ".payload.baseUrl"},
                {"action": "UPDATE", "method": "PUT", "url": ".payload.baseUrl", "body": ".payload.body"},
                {"action": "REMOVE", "method": "DELETE", "url": ".payload.baseUrl"},
            ],
            # L'API renvoie la définition sous .data : titre, description et panneaux comparés.
            ".response.statusCode == 200"
            " and .response.body.data.title == .payload.body.title"
            " and .response.body.data.description == .payload.body.description"
            " and (.response.body.data.panels | length) == (.payload.body.panels | length)",
            # provider-http évalue les valeurs d'en-tête en jq : 2023-10-31 serait une soustraction.
            {"Elastic-Api-Version": ['"2023-10-31"']},
        )


def main():
    docs = list(dashboards())
    for d in docs:
        sys.stdout.write("---\n" + json.dumps(d, ensure_ascii=False, indent=1) + "\n")
    print(f"{len(docs)} requêtes Kibana générées", file=sys.stderr)


if __name__ == "__main__":
    main()
