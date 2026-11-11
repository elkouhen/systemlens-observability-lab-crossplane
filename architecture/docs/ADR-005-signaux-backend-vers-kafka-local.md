# ADR-005 : acheminer tous les signaux du backend vers le Kafka local

## Statut

Superseded par [ADR-021](ADR-021-hub-de-gestion-et-clusters-cibles.md) (2026-11-11 : la VM
`otel-backend-01` est supprimée, le collecteur backend tourne dans `k3s-01`). Auparavant accepted, supersedes ADR-004

Précisé par [ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md) :
l'agent publie dans les topics de sa plateforme,
`otel-<signal>-elk-homologation`, déclarés par `otel_edge: kafka-local`.

## Date

2026-09-28

## Contexte

`otel-backend-01` ne doit pas dépendre de la connectivité OTLP vers
`otel-edge-01`. Le broker Kafka OTel local et le backend OTel consomment
déjà les topics `otel-traces`, `otel-metrics` et `otel-logs`.

## Décision

L'agent EDOT de `otel-backend-01` publie directement ses métriques, logs,
traces et sa télémétrie interne dans le broker Kafka OTel local
(`127.0.0.1:9092`), avec l'encodage `otlp_proto`. Aucun pipeline de l'agent
backend n'utilise l'exporteur `otlphttp/edge`.

Le backend OTel consomme les trois topics et envoie les métriques et
logs vers Elasticsearch ainsi que les traces vers APM Server.

```text
EDOT backend → Kafka OTel local → backend OTel
                              ├── métriques + logs → Elasticsearch
                              └── traces → APM Server
```

La configuration reste standalone et versionnée dans Ansible. Fleet conserve
uniquement la supervision OpAMP.

## Sécurité des identités et des flux

La chaîne Edge, Kafka, Backend, Elasticsearch et APM doit utiliser une
identité distincte par rôle. Une même clé ne doit pas être partagée entre les
collecteurs, Kafka, Elasticsearch et APM Server.

```text
otel-edge
  └── identité Kafka producteur
       └── droits d'écriture sur les topics OTel

otel-backend
  ├── identité Kafka consommateur
  │    └── droits de lecture sur les topics OTel
  ├── clé API Elasticsearch
  │    └── droits d'écriture limités aux data streams OTel
  └── token secret APM Server
       └── droits d'ingestion APM
```

Le flux Edge vers Backend passe par Kafka. L'identité du collecteur Edge doit
donc être autorisée à publier sur `otel-traces`, `otel-metrics` et `otel-logs`.
L'identité du backend doit être limitée à la consommation de ces mêmes topics.
Kafka doit utiliser TLS et une authentification client, par SASL ou par
certificat, selon le mécanisme retenu pour l'installation.

Le backend utilise une clé API Elasticsearch dédiée à l'exporteur
`elasticsearch/otel`. Cette clé doit autoriser l'écriture dans les data
streams OTel requis et ne doit pas fournir de droits d'administration, de
lecture générale ou de gestion des utilisateurs.

Le backend utilise un token secret APM dédié à l'exporteur
`otlphttp/apm-server`. Ce token est distinct de la clé Elasticsearch et doit
être transmis uniquement sur HTTPS.

Les secrets sont conservés hors Git et injectés dans l'environnement local du
backend avec des permissions restrictives. Les clés Kafka Edge et Backend,
la clé API Elasticsearch et le token APM doivent pouvoir être renouvelés
indépendamment, avec une période de recouvrement permettant de vérifier le
nouveau chemin avant la révocation de l'ancien secret.

Les templates Edge et les exporteurs OTLP utilisent maintenant ces clés Bearer.
Les clés Kubernetes sont versionnées chiffrées par SOPS (`gitops/<groupe>/secrets/otel-edge-client-keys.sops.yaml`)
à partir
des variables d'environnement `OTEL_EDGE_KEY_KUBERNETES` et
`OTEL_EDGE_KEY_KUBERNETES_CLUSTER`. Les clés des agents VM sont fournies à
Ansible avec `OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE`,
`OTEL_EDGE_KEY_EDGE_AGENT` et `OTEL_EDGE_KEY_ELK_AGENT`.

Le transport OTLP reste à chiffrer avec TLS. Une clé Bearer ne doit pas être
considérée comme protégée tant que les endpoints Edge utilisent encore HTTP.

## Alternatives considérées

### Conserver l'envoi des logs et traces vers Edge

Cette option est écartée car elle conserve une dépendance réseau inutile pour
le backend et contredit l'objectif d'un chemin local complet.

### Ajouter un collecteur local distinct

Cette option est écartée car l'agent EDOT sait publier les trois types de
signaux dans Kafka et l'exporteur existant sait déjà les consommer.

## Conséquences

- aucun signal produit par l'agent backend ne dépend d'Edge ;
- les topics `otel-traces`, `otel-metrics` et `otel-logs` deviennent le contrat
  local de production et d'export ;
- le broker Kafka local devient une dépendance directe de l'agent backend pour
  tous ses signaux ;
- la recette doit vérifier les trois topics et la présence des données
  correspondantes dans Elasticsearch et APM Server.

## Références

- [`ansible/roles/elastic_agent/templates/elastic-agent.yml.j2`](../ansible/roles/elastic_agent/templates/elastic-agent.yml.j2)
- [`ansible/roles/otel_backend/templates/otel-backend.yaml.j2`](../ansible/roles/otel_backend/templates/otel-backend.yaml.j2)
- [`ansible/README.md`](../ansible/README.md)
- [`docs/ADR-004-metrics-backend-vers-kafka-local.md`](ADR-004-metrics-backend-vers-kafka-local.md)
