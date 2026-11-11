# ADR-004 : acheminer les métriques du backend vers le Kafka local

## Statut

Accepted

## Date

2026-09-28

## Contexte

L'agent EDOT de `otel-backend-01` collecte les métriques système de la VM et
les métriques du broker Kafka local. Le chemin nominal des agents VM passe par
le Collecteur EDOT Edge en OTLP, mais cette connectivité n'est pas disponible
pour le backend. Le backend héberge déjà le Kafka OTel et l'exporteur qui
consomme le topic `otel-metrics`.

Un chemin de repli doit conserver le format OTLP, le découplage par Kafka et
l'indexation existante dans Elasticsearch, sans ajouter un collecteur local
ou modifier la policy Fleet.

## Décision

L'agent EDOT de `otel-backend-01` publie directement ses métriques dans le
broker Kafka OTel local (`127.0.0.1:9092`), sur le topic `otel-metrics`, avec
l'encodage `otlp_proto`. Les métriques système, les métriques Kafka locales et
la télémétrie interne de l'agent utilisent ce chemin.

Les logs et traces de l'agent backend conservent l'export OTLP vers
`otel-edge-01`. L'exporteur Kafka EDOT consomme ensuite `otel-metrics` et
exporte les métriques vers Elasticsearch comme les autres métriques OTel.

```text
EDOT backend → Kafka OTel local / otel-metrics → exporteur Kafka EDOT → Elasticsearch
```

La configuration reste standalone et versionnée dans Ansible. Fleet conserve
uniquement la supervision OpAMP.

## Alternatives considérées

### Conserver l'envoi OTLP vers Edge

Cette option n'est pas applicable tant que `otel-backend-01` ne peut pas
atteindre l'endpoint OTLP d'Edge. Elle laisserait les métriques de la VM sans
chemin de collecte fonctionnel.

### Ajouter un nouveau collecteur local

Cette option est écartée car l'agent EDOT sait déjà produire des messages
Kafka OTLP et le backend possède déjà le broker ainsi que le consommateur du
topic `otel-metrics`. Un nouveau processus augmenterait la surface
d'exploitation sans bénéfice fonctionnel.

### Exporter directement vers Elasticsearch

Cette option est écartée pour conserver le buffering Kafka et le même chemin
d'indexation que les autres métriques OTel.

## Conséquences

- les métriques du backend ne dépendent plus de la connectivité vers Edge ;
- le topic `otel-metrics` reste le contrat commun entre production et export ;
- le broker Kafka local devient une dépendance directe de l'agent backend pour
  les métriques ;
- les logs et traces du backend restent dépendants d'Edge ;
- la recette doit vérifier l'état de l'agent, le topic Kafka et la présence
  récente des métriques backend dans Elasticsearch.

## Références

- [`ansible/roles/elastic_agent/templates/elastic-agent.yml.j2`](../ansible/roles/elastic_agent/templates/elastic-agent.yml.j2)
- [`ansible/roles/otel_backend/templates/otel-backend.yaml.j2`](../ansible/roles/otel_backend/templates/otel-backend.yaml.j2)
- [`ansible/README.md`](../ansible/README.md)
