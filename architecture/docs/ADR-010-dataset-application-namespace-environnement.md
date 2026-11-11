# ADR-010 : le dataset nomme l'application, le namespace l'environnement

## Statut

Accepted. La partie traces (namespace `<plateforme>_<environnement>`,
`apm.route.namespace`, pipeline `apm-route-namespace`) est remplacée par
[ADR-018](ADR-018-traces-otel-natives-sans-apm-server.md) : les traces
suivent la règle commune, dataset de l'application et namespace de
l'environnement. La règle de namespace est remplacée par
[ADR-019](ADR-019-namespace-par-plateforme.md) : le namespace vaut
`<plateforme>_<environnement>`, et une application n'a plus de dataset
propre : ses signaux OTLP gardent `generic`.

Remplace la partie « nommage des data streams » de
[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md). Le choix du topic Kafka
par le collecteur Edge (ADR-009) reste en vigueur.

Amendé par [ADR-012](ADR-012-logs-otel-natifs-sans-ecs.md) : les logs sont en
mode de mapping OTel et leur data stream prend le suffixe `.otel`.

Amendé par la note « dataset et namespace portés par le topic » du
2026-11-02, en fin de document : les puces **Dataset** et **Namespace**
ci-dessous, ainsi que la composition `<dataset>_<environnement>` de la note
APM, sont remplacées. Les noms des data streams ne changent pas.

## Date

2026-11-02

## Contexte

ADR-009 utilisait le namespace de data stream pour séparer les flux :
`traces-apm-supermarche`, `metrics-generic.otel-supermarche`,
`logs-filelogreceiver-supermarche`, `metrics-kubeletstatsreceiver.otel-k8s`.
La convention Elastic est inverse : le dataset décrit ce qui est collecté, le
namespace décrit où (environnement, équipe). Le namespace `supermarche`
masquait l'environnement `homologation` et le dataset `generic` ne disait pas
quelle application émettait.

## Décision

Le dataset nomme l'application ou la plateforme ; le namespace nomme
l'environnement. Les topics `otel-<signal>-supermarche` et
`otel-<signal>-k8s` d'ADR-009 sont conservés pour isoler les flux dans Kafka.

- **Dataset** : posé par le collecteur Edge, dans le processor
  `transform/kafka-topic`, sur les logs et métriques d'une route applicative
  (`otel_edge_application_routes[].data_stream_dataset`, ici `supermarche`).
  Les traces ne reçoivent aucun dataset : APM Server garde `apm` et
  `apm.error`, lus par l'UI APM et par SystemLens.
- **Namespace** : posé par le collecteur backend, dans
  `transform/data-stream-namespace`, pour tout topic suffixé. Il vaut
  `deployment.environment.name`, sinon `deployment.environment`, sinon
  `default`, normalisé en `[a-z0-9_]`. Les topics de base (VM, Edge, Fleet)
  ne changent pas.
- **Kubernetes** : les signaux des collecteurs Kubernetes gardent le dataset
  de leur receiver. Les 11 dashboards du package `kubernetes_otel` 2.6.1 et
  les dashboards `[OTel] Host` interrogent
  `metrics-kubeletstatsreceiver.otel-*`, `metrics-k8sclusterreceiver.otel-*`
  et `metrics-hostmetricsreceiver.otel-*`. Un dataset unique `k8s` les
  viderait, et ces dashboards sont gérés par Fleet, pas par ce dépôt.
- Les collecteurs Kubernetes posent `deployment.environment.name` =
  `homologation` (`resource/environment`, sans écraser une valeur de la
  source) : leurs métriques portent ainsi l'environnement. Les logs
  applicatifs le tiennent de l'agent OTel (`deployment.environment`).
- En mode de mapping OTel, l'exporteur Elasticsearch ajoute `.otel` au
  dataset des métriques et, depuis ADR-012, des logs ; les templates
  `metrics-*.otel-*` et `logs-*.otel-*` s'appliquent.

| Signal | Data stream |
| --- | --- |
| Logs des services `supermarket-demo` | `logs-supermarche.otel-homologation` (ADR-012) |
| Métriques Micrometer | `metrics-supermarche.otel-homologation` |
| Métriques runtime de l'agent Java OTel | `metrics-apm.app.<service>-<plateforme>_<environnement>` ([ADR-016](ADR-016-metriques-agent-otel-vers-apm-server.md)) |
| Traces | `traces-apm-supermarche_homologation` (note du 2026-11-02) |
| Erreurs APM | `logs-apm.error-supermarche_homologation` (note du 2026-11-02) |
| Métriques Kubernetes | `metrics-{kubeletstatsreceiver,k8sclusterreceiver,hostmetricsreceiver,prometheusreceiver}.otel-homologation` |
| Métriques APM agrégées | `metrics-apm.*.1m-supermarche_homologation` (note du 2026-11-02) |
| Signaux des VM | inchangés, namespace `default` |

## Alternatives considérées

- **Dataset unique `k8s` pour les collecteurs Kubernetes** : rejeté, les
  dashboards Fleet `[Kubernetes OTel]` et `[OTel] Host` ne trouveraient plus
  de données.
- **Le backend déduit le dataset du suffixe du topic** : le suffixe `k8s` ne
  doit pas devenir un dataset, et les traces doivent garder `apm`. La règle
  par route, posée par l'Edge à côté du choix du topic, reste plus lisible.

## Conséquences

- Le suffixe du topic n'est plus un namespace : il isole un flux routé dans
  Kafka et indique au backend d'appliquer l'environnement
  ([ADR-007](ADR-007-namespace-data-stream-par-topic.md), note du
  2026-11-02).
- Le dashboard métier, le data view APM et les contrôles
  `dashboards-verify` et `observability-schema-verify` lisent
  `metrics-supermarche.otel-*` et `logs-supermarche.otel-*` (ADR-012).
- APM Server ne reprend pas le namespace des traces pour ses métriques
  agrégées. Depuis la note du 2026-11-02, un pipeline Elasticsearch les range
  dans le namespace des traces de la route applicative. Les motifs
  `metrics-apm.<métrique>.<intervalle>-*` les trouvent toujours.
- Une nouvelle application déclare son dataset dans sa route Edge ; son
  namespace suit son `deployment.environment`.

## Vérification

Le 2026-11-02, après `make otel-edge-vm-provision`,
`make otel-backend-vm-provision` et `make kubernetes-observability-deploy`,
les data streams du tableau reçoivent les nouveaux documents. Les data streams
`*-supermarche` et `*.otel-k8s` ne reçoivent plus rien. Les contrôles
`trace-context-verify`, `observability-schema-verify`, `dashboards-verify` et
`kubernetes-otel-dashboards-verify` réussissent.

## Note du 2026-11-02 : namespace des signaux APM

Exigence validée : chaque data stream de l'application en homologation nomme
l'application et l'environnement. APM Server impose les datasets `apm`,
`apm.error` et `apm.*` lus par l'UI APM. Les signaux APM d'une route
applicative prennent donc le namespace `<dataset de la route>_<environnement>`,
normalisé en `[a-z0-9_]`. Les logs, les métriques, la route Kubernetes et
les topics de base ne changent pas.

| Signal de `supermarche` en homologation | Data stream |
| --- | --- |
| Traces | `traces-apm-supermarche_homologation` |
| Erreurs APM | `logs-apm.error-supermarche_homologation` |
| Métriques APM agrégées | `metrics-apm.{transaction,service_transaction,service_destination,service_summary}.1m-supermarche_homologation` |
| Logs | `logs-supermarche.otel-homologation` (ADR-012) |
| Métriques | `metrics-supermarche.otel-homologation` |

### Traces et erreurs

- L'Edge pose `otel.route.dataset` (dataset de la route) sur les traces de la
  route, après avoir supprimé toute valeur fournie par le client. Il ne pose
  pas `data_stream.dataset` sur les traces : APM Server l'utiliserait comme
  dataset et l'UI APM ne lirait plus `traces-apm*`.
- Le backend, pour un topic `otel-traces-<suffixe>`, compose
  `data_stream.namespace` = `<otel.route.dataset>_<environnement>`, puis
  supprime `otel.route.dataset`. Sans route (Kubernetes), le namespace reste
  l'environnement. APM Server garde le namespace posé par l'événement
  (`SetDataStream` d'apm-data) pour les transactions, spans et erreurs.

### Métriques agrégées

Analyse du code d'APM Server 9.5.4 (apm-data 1.22.2, apm-aggregation 1.5.1) :

- Les clés d'agrégation (`ServiceAggregationKey`, `TransactionAggregationKey`,
  etc.) ne contiennent pas le namespace. Les métriques produites n'ont pas de
  data stream ; le processeur final `SetDataStream` leur donne
  `apm-server.data_streams.namespace` (ou le namespace de la policy Fleet),
  une valeur unique pour tout APM Server.
- Les clés contiennent en revanche les labels globaux, c'est-à-dire les
  attributs de ressource OTLP non reconnus. Ils sont reportés sur les
  métriques agrégées.
- Les pipelines `metrics-apm.<métrique>@default-pipeline` gérés par
  Elasticsearch existent « pour le routage » et appellent
  `metrics-apm.<métrique>@custom` : un `reroute` y est pris en charge.

Décision : le backend recopie le namespace composé dans l'attribut de
ressource `apm.route.namespace`, après avoir supprimé toute valeur reçue :
seul le backend le pose. APM Server en fait le label global
`apm_route_namespace`. Le pipeline Elasticsearch `apm-route-namespace`
(`platform/elk/ingest/`, installé par `make apm-ingest-pipelines-deploy`) est
appelé par `traces-apm@custom`, `logs-apm.error@custom`,
`logs-apm.app@custom` et les quatre `metrics-apm.<métrique>@custom`. Il
retire le label de chaque document et, pour une métrique, pose ce namespace
puis appelle `reroute`. Le label n'est donc jamais indexé ; les agrégats des
traces sans route restent dans `default`.

Alternatives écartées :

- **`apm-server.data_streams.namespace` global** : déplace toutes les sorties
  d'APM Server sans namespace propre (VM, collecteurs) dans un seul
  namespace. Une seule application possible.
- **Une instance APM Server par application et environnement** : chaque
  instance a son namespace global ; le backend route les traces par
  application (connecteur `routing`). Coût : un conteneur, un port, un token
  et quelques centaines de Mo de mémoire par couple, plus la configuration du
  backend.
- **Agrégats calculés par le collecteur (connecteur `elasticapm`)** : absent
  de contrib (ADR-006), il imposerait une distribution EDOT ou un build
  personnalisé du collecteur, et la désactivation des agrégats d'APM Server.

Conséquences :

- Le label ajoute une dimension aux agrégats d'APM Server, de valeur unique
  par service : le nombre de groupes ne change pas.
- `sync-fleet-policies.sh` ne supprime plus `traces-apm@custom`, désormais
  géré par `sync-apm-ingest-pipelines.sh`.
- Les pipelines doivent être installés avant le backend : sinon le label est
  indexé dans `labels.apm_route_namespace`. `make` les installe juste après
  `elasticsearch-ready`.

Vérification du 2026-11-02 : après `make apm-ingest-pipelines-deploy`,
`make otel-backend-vm-provision` et `make otel-edge-vm-provision`, les trois
services écrivent dans les data streams du tableau. `traces-apm-homologation`
et `metrics-apm.*.1m-default` ne reçoivent plus rien pour eux. Aucun document
APM ne porte `labels.apm_route_namespace`. L'UI APM liste les services et
leurs erreurs ; les contrôles `trace-context-verify`,
`observability-schema-verify`, `dashboards-verify` et
`kubernetes-otel-dashboards-verify` réussissent.

## Note du 2026-11-02 : dataset et namespace portés par le topic

Décision produit, simplification : le dataset et le namespace d'un flux routé
sont déclarés une seule fois, par la route Edge, dans le nom de son topic
(`kafka_topic: supermarche-homologation`). Le backend les lit dans le topic
([ADR-007](ADR-007-namespace-data-stream-par-topic.md), note du 2026-11-02).

| Avant | Après |
| --- | --- |
| Edge : `data_stream.dataset` sur les logs et métriques, `otel.route.dataset` sur les traces | Edge : choix du topic seul, attributs de routage du client supprimés |
| Backend : namespace = `deployment.environment.name`, sinon `deployment.environment`, sinon `default`, normalisé | Backend : namespace = segment `<namespace>` du topic |
| Backend : traces en `Concat(otel.route.dataset, environnement)` | Backend : traces en `<dataset>_<namespace>` du topic |
| Topics `otel-<signal>-supermarche`, `otel-<signal>-k8s` | Topics `otel-<signal>-supermarche-homologation`, `otel-<signal>-homologation` |

Pourquoi : la règle tenait en trois endroits (route Edge, attribut
d'environnement de chaque source, calcul du backend) pour une valeur connue à
l'avance. Le topic suffit, et Kafka montre où va chaque flux.

Conséquences :

- Une route vise un seul environnement : l'Edge d'homologation publie en
  `homologation`. Une application déployée dans un autre environnement reçoit
  sa propre route et ses topics.
- `deployment.environment.name` ne fixe plus le namespace. Il reste porté par
  les sources, pour `service.environment` dans l'UI APM. Les applications
  utilisent ce nom courant d'OpenTelemetry au lieu de
  `deployment.environment` ; APM Server 9.5.4 le reporte en
  `service.environment` = `homologation`.
- Les noms sont validés par Ansible au déploiement, plus normalisés à
  l'exécution.

Vérification du 2026-11-02 : les data streams du tableau d'ADR-010, de sa
note APM et d'ADR-012 reçoivent les nouveaux documents, métriques APM
agrégées comprises (`metrics-apm.*.1m-supermarche_homologation` pour les trois
services). Aucun data stream n'a été créé et aucun document ne porte
`otel.kafka.topic` ou `labels.apm_route_namespace`. L'UI APM liste les trois
services en `homologation`.
