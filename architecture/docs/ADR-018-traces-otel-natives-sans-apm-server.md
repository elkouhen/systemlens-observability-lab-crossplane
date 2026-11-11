# ADR-018 : indexer les traces en OTel natif, sans APM Server ni ECS

## Statut

Accepted, déployé le 2026-11-08.

Remplace [ADR-016](ADR-016-metriques-agent-otel-vers-apm-server.md) et la
partie traces d'[ADR-010](ADR-010-dataset-application-namespace-environnement.md)
(namespace `<plateforme>_<environnement>`, label `apm_route_namespace`,
pipeline `apm-route-namespace`). Étend
[ADR-012](ADR-012-logs-otel-natifs-sans-ecs.md) à tous les signaux.

## Date

2026-11-08

## Contexte

Les logs et les métriques étaient indexés en OTel natif (ADR-012), mais les
traces et les métriques de l'agent Java passaient par APM Server. Celui-ci
convertit les données en ECS : attributs rangés dans `labels.*`, datasets
`apm.*` imposés, namespace détourné pour séparer les plateformes. Elastic
qualifie ce chemin de « legacy ingest path » ; pour une stack 9.x autogérée,
sa référence est un collecteur EDOT en mode gateway qui indexe les traces en
OTel natif avec le processeur et le connecteur `elasticapm`. Le lab ne veut
aucune conversion ECS.

## Décision

- Le collecteur backend applique le processeur `elasticapm` aux traces
  (classification transaction/span, résultat, dépendances) et les exporte
  en mode `otel` vers Elasticsearch.
- Le connecteur `elasticapm` calcule depuis les traces les métriques
  agrégées de l'UI APM (`metrics-{transaction,service_transaction,
  service_destination,service_summary}.<intervalle>.otel-<env>`).
- Toutes les métriques, celles de l'agent Java comprises, vont à
  Elasticsearch en OTel natif : le connecteur `routing/metrics` et
  l'exporteur APM Server sont retirés.
- L'Edge pose le dataset de la plateforme sur les trois signaux :
  `traces-<dataset>.otel-<env>` comme les logs et les métriques. Le
  namespace est l'environnement, la plateforme est `platform.id`.
- Le label `apm.route.namespace` et les pipelines Elasticsearch
  `apm-route-namespace` sont retirés du dépôt.
- Le backend pose aussi l'ancien attribut `deployment.environment` sur les
  trois signaux. Les templates OTel d'Elasticsearch en font l'alias
  `service.environment`, par lequel l'UI APM filtre les logs, métriques et
  traces d'un service ; sans lui, l'onglet Logs d'un service est vide.
  `make observability-schema-verify` le contrôle.

| Signal | Data stream |
| --- | --- |
| Traces de `supermarket-demo` | `traces-supermarche.otel-homologation` |
| Traces de `demo-api` | `traces-demo.otel-homologation` |
| Métriques JVM et HTTP de l'agent | `metrics-<dataset>.otel-homologation` |
| Métriques APM agrégées | `metrics-service_transaction.1m.otel-homologation`, etc. |

## Alternatives considérées

- **Garder APM Server** : rejeté, il convertit en ECS.
- **Envoyer en OTLP au Managed OTLP Endpoint** : réservé à Elastic Cloud.
- **Ajouter `traces-*.otel-*` aux index de l'UI APM sans `elasticapm`** :
  sans métriques agrégées ni classification, l'UI APM est incomplète.

## Conséquences

- Un seul modèle de données, OTel natif, pour logs, métriques et traces.
  `trace.id`, `span.id`, `service.name` restent disponibles en alias.
- APM Server est retiré d'`elk-01` : unité, configuration, jeton
  `APM_SERVER_SECRET_TOKEN`, port 8200 et cible `apm-token-show`. Le rôle
  `elk` arrête et supprime le service d'une VM déjà provisionnée.
- Les données APM antérieures restent dans `traces-apm*` et `metrics-apm*`
  jusqu'à leur expiration ILM. Les pipelines `*-apm*@custom` et
  `apm-route-namespace` déjà installés ne reçoivent plus de documents.
- Le connecteur `elasticapm` agrège en mémoire : un seul collecteur backend,
  comme pour `cumulative_to_delta`.

## Vérification

`make otel-config-validate`, `make otel-backend-vm-provision`,
`make otel-edge-vm-provision`, puis `make otel-routing-verify`,
`make trace-context-verify`, `make observability-schema-verify`,
`make dashboards-verify` et `make demo-api-jvm-metrics-verify`. L'UI APM
liste les services depuis les métriques agrégées OTel natives.
