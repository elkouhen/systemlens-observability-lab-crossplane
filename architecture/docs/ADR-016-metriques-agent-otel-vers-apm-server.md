# ADR-016 : envoyer les métriques de l'agent Java OpenTelemetry à APM Server

## Statut

Superseded par [ADR-018](ADR-018-traces-otel-natives-sans-apm-server.md) le
2026-11-08 : les métriques de l'agent sont indexées en OTel natif.

Accepted, déployé le 2026-11-07.

Amende [ADR-012](ADR-012-logs-otel-natifs-sans-ecs.md) (tous les flux indexés
en mapping OTel) et [ADR-010](ADR-010-dataset-application-namespace-environnement.md)
(tableau des data streams) pour les seules métriques de l'agent Java OTel.
Conserve [ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md)
(topics par plateforme) et [ADR-013](ADR-013-livraison-kafka-et-telemetrie-interne.md)
(livraison Kafka).

## Date

2026-11-07

## Contexte

Depuis ADR-008, l'agent Java OpenTelemetry de `demo-api` exporte les
métriques runtime JVM de la sémantique OTel (`jvm.memory.used`,
`jvm.gc.duration`, `jvm.thread.count`…). Le collecteur backend les indexait,
comme toutes les métriques, en mapping OTel natif dans
`metrics-demo.otel-homologation`.

Les traces du même service passent par APM Server : Kibana traite donc le
service comme un service APM « classique » et l'onglet *Metrics* de l'UI APM
lit ses métriques dans `metrics-apm*`. Les métriques JVM, hors de ce motif,
n'y apparaissaient pas ; latence, débit et erreurs s'affichaient, car ils
sont calculés à partir des traces.

Les métriques Micrometer de `supermarket-demo` (agent avec
`otel.metrics.exporter=none`) alimentent le dashboard métier et les alertes,
qui interrogent `metrics-supermarche.otel-*`. Elles ne doivent pas changer de
data stream.

## Décision

- Le collecteur backend partage le flux de métriques avec le connecteur
  `routing/metrics` (contexte `metric`). Les métriques dont le scope
  d'instrumentation commence par `io.opentelemetry.` (runtime JVM,
  instrumentation HTTP et SDK de l'agent) vont au pipeline `metrics/apm` ;
  toutes les autres vont au pipeline `metrics/elasticsearch`, inchangé.
- `metrics/apm` applique `transform/apm-route`, partagé avec les traces
  depuis la note du 2026-11-08 d'ADR-015 : suppression de
  `data_stream.dataset` posé par l'Edge (APM Server garde `apm.app`) et
  namespace `<plateforme>_<environnement>`, comme les traces (note du
  2026-11-02 d'ADR-010), recopié dans `apm.route.namespace` : APM Server
  calcule aussi des agrégats `service_summary` depuis les métriques, qui
  tomberaient sinon dans `default`. Il exporte vers `otlphttp/apm-server`,
  avec la même file persistante que les traces.
- Le pipeline `apm-route-namespace` est appelé aussi par
  `metrics-apm.app@custom` et `metrics-apm.internal@custom`, pour retirer le
  label de ces documents.
- Les trois services de `supermarket-demo` activent les métriques de leur
  agent (`otel.metrics.exporter=otlp`, intervalle 15 s). Leurs métriques
  métier restent émises par Micrometer ; le pont Micrometer de l'agent reste
  désactivé (défaut de l'agent 2.x). Le ConfigMap n'ayant pas de suffixe de
  hash, `make apps-restart` recharge la configuration.
- `filter/invalid-double` et `cumulativetodelta` restent appliqués avant le
  partage, pour les deux destinations.

| Métriques | Data stream |
| --- | --- |
| Agent Java OTel de `demo-api` | `metrics-apm.app.demo_api-demo_homologation` |
| Agent Java OTel de `supermarket-demo` | `metrics-apm.app.<service>-supermarche_homologation` |
| Métriques connues d'APM Server (`jvm.thread.count`…) | `metrics-apm.internal-<plateforme>_<environnement>` |
| Micrometer de `supermarket-demo` | `metrics-supermarche.otel-homologation` (inchangé) |
| Kubernetes, hôtes, télémétrie interne | inchangés |

## Alternatives considérées

- **Envoyer toutes les métriques applicatives à APM Server** : rejeté, le
  dashboard métier et les alertes lisent les métriques Micrometer dans
  `metrics-supermarche.otel-*`.
- **Ajouter `metrics-*.otel-*` aux index de métriques de l'UI APM** : rejeté,
  le comportement de l'onglet *Metrics* pour un service aux traces classiques
  et aux métriques OTel natives n'est pas garanti, et le réglage vit dans
  Kibana, hors du dépôt.
- **Faire indexer les traces en OTel natif** : hors périmètre, APM Server
  calcule les métriques agrégées et les erreurs lues par l'UI APM et
  SystemLens.

## Conséquences

- Les métriques d'un même service Java OTel suivent le modèle de ses traces ;
  les logs restent en OTel natif (ADR-012).
- APM Server stocke les attributs de point comme labels
  (`labels.jvm_memory_type`, `labels.jvm_memory_pool_name`…) et les noms de
  métriques sans préfixe `metrics.`.
- Une nouvelle application instrumentée par l'agent, métriques activées,
  apparaît dans l'onglet *Metrics* sans configuration supplémentaire.
- Les documents JVM déjà indexés dans `metrics-demo.otel-homologation`
  y restent jusqu'à leur expiration ILM.

## Vérification

Déploiement : `make otel-config-validate`, `make otel-gateway-vm-provision`,
`make apm-ingest-pipelines-deploy`, `make apps-deploy` puis
`make apps-restart`. Contrôle du 2026-11-07 :

- `make demo-api-jvm-metrics-verify` : `OK` pour les six métriques dans
  `metrics-apm.app.demo_api-*` et `metrics-apm.internal-*` ;
- data streams `metrics-apm.app.{order,inventory,restock}_service-supermarche_homologation`
  alimentés ; aucun document APM récent dans un namespace `default` ;
- aucun document du scope `io.opentelemetry.runtime-telemetry-java8` dans
  `metrics-demo.otel-*` sur les deux dernières minutes ;
- `metrics-supermarche.otel-*` et `metrics-kubeletstatsreceiver.otel-*`
  continuent de recevoir des documents ;
- Kibana, APM, onglet *Indicateurs* de `demo-api` et `order-service` :
  tableau JVM (CPU, heap, non-heap, threads) et graphiques renseignés.
