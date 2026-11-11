# ADR-009 : séparer les namespaces de data stream `supermarche` et `k8s`

## Statut

Accepted, partiellement remplacé

Depuis [ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md), la
table de l'Edge est celle des plateformes du cluster (`otel_edge_cluster`,
`otel_edge_namespace_routes`) et des VM rattachées ; le marqueur des
collecteurs Kubernetes et la priorité des règles restent ceux décrits ici.

Depuis [ADR-020](ADR-020-plateforme-declaree-par-le-client.md), le marqueur
`otel.edge.source` et la priorité des règles disparaissent : chaque client
déclare `platform.id` et `deployment.environment.name`.

Le 2026-11-02, [ADR-010](ADR-010-dataset-application-namespace-environnement.md)
remplace le nommage des data streams : le dataset nomme l'application
(`supermarche`) et le namespace l'environnement (`homologation`). Le choix des
topics `otel-<signal>-supermarche` et `otel-<signal>-k8s` par l'Edge reste en
vigueur.

Depuis [ADR-012](ADR-012-logs-otel-natifs-sans-ecs.md), les logs des trois
services viennent de l'agent OTel et non plus de stdout ; la règle
`k8s.namespace.name` les route toujours dans `otel-logs-supermarche`.

Depuis la note du 2026-11-02 en fin de document, les topics routés sont
`otel-<signal>-supermarche-homologation` et `otel-<signal>-homologation`, et
l'Edge supprime les attributs de routage fournis par les clients.

## Date

2026-11-02

## Contexte

Tous les signaux reçus par le collecteur Edge partaient dans les topics de
base et étaient écrits dans le namespace `default`. Les signaux des
applications `supermarket-demo`, ceux des collecteurs Kubernetes et ceux des
VM se mélangeaient donc dans les mêmes data streams.

[ADR-007](ADR-007-namespace-data-stream-par-topic.md) fournit le mécanisme :
le backend dérive `data_stream.namespace` du suffixe du topic
`otel-<signal>-<namespace>`. Il restait à choisir qui publie dans ces topics.

Le jeton OTLP ne distingue pas les émetteurs : les agents Java des
applications utilisent la même clé Edge que `otel-kubernetes-cluster`.

## Décision

Le collecteur Edge choisit le topic de chaque ressource. Cette décision amende
ADR-007, selon lequel l'Edge publiait uniquement dans les topics de base.

- Namespace `supermarche` : signaux dont la ressource porte
  `k8s.namespace.name` = `h0tl-supermarche-app`. Cela couvre les traces, les
  erreurs APM, les métriques Micrometer et JVM et les logs stdout des trois
  services.
- Namespace `k8s` : signaux des collecteurs `otel-kubernetes` et
  `otel-kubernetes-cluster`. Ils posent l'attribut de ressource
  `otel.edge.source=kubernetes` : `kubeletstats`, `k8s_cluster`,
  `hostmetrics` de `k3s-01` et leur propre télémétrie Prometheus.
- Namespace `default` : tout le reste (agents EDOT des VM, télémétrie des
  collecteurs Edge et backend, Fleet).
- Un log suit le namespace Kubernetes de son pod : la règle applicative passe
  avant le marqueur. Une métrique ou une trace suit son émetteur : le marqueur
  passe avant. Les métriques `kubeletstats` d'un pod applicatif vont donc dans
  `k8s`, ses logs stdout dans `supermarche`.
- Le processor `transform/kafka-topic` de l'Edge pose `otel.kafka.topic` ;
  l'exporteur Kafka le lit par `topic_from_attribute` et publie chaque
  ressource dans son topic. Une valeur envoyée par un client est d'abord
  supprimée. Le marqueur est supprimé par l'Edge, `otel.kafka.topic` par le
  backend : aucun des deux n'est indexé.
- Les règles sont des variables Ansible
  (`inventory/group_vars/otel_edge_nodes.yml`). Le job
  `otel-telemetry-topics` crée les six topics suffixés avec trois partitions
  et la rétention des topics de base.

## Alternatives considérées

- **Connector `routing` et un exporteur Kafka par topic** : aucun attribut
  technique transitoire, mais neuf pipelines au lieu de trois.
- **Distinguer les clients par leur jeton** : impossible tant que les
  applications partagent la clé de `otel-kubernetes-cluster`.
- **Poser `data_stream.namespace` dans chaque source** : rejeté par ADR-007,
  car la règle serait dispersée et Kafka ne séparerait pas les flux.

## Conséquences

- Les données antérieures au 2026-11-02 restent dans les data streams
  `*-default` jusqu'à leur expiration ILM. Une requête sur une période qui
  couvre la bascule doit viser `*-default` et le nouveau namespace.
- Les métriques APM agrégées par APM Server (`metrics-apm.*`) restent dans
  `default` : APM Server les calcule sans reprendre le namespace des traces
  sources. Les motifs `metrics-apm.<métrique>.<intervalle>-*` les trouvent
  toujours.
- Une nouvelle application obtient son namespace par une entrée de
  `otel_edge_application_routes` et trois topics dans le job
  `otel-telemetry-topics`.
- Les dashboards et data views fondés sur `metrics-*`, `logs-*` ou
  `traces-apm*` ne changent pas.

## Vérification

Après `make otel-edge-vm-provision` et `make kubernetes-observability-deploy`,
les traces et erreurs APM, les métriques `generic.otel` et les logs
`filelogreceiver` des trois services arrivent dans `*-supermarche`. Les
métriques `kubeletstatsreceiver`, `k8sclusterreceiver`,
`prometheusreceiver` et `hostmetricsreceiver` de `k3s-01` arrivent dans
`*-k8s`. Les signaux des VM restent dans `default`. Les contrôles
`trace-context-verify`, `observability-schema-verify`, `dashboards-verify` et
`kubernetes-otel-dashboards-verify` réussissent.

## Note du 2026-11-02 : l'Edge choisit le topic, le topic porte la cible

[ADR-007](ADR-007-namespace-data-stream-par-topic.md) (note du 2026-11-02)
fait porter au nom du topic le dataset et le namespace, que le backend
reporte sur les signaux. L'Edge ne pose plus aucun attribut de data stream ;
il choisit le topic de chaque ressource selon la même priorité qu'ici.

```yaml
otel_edge_application_routes:
  - kubernetes_namespace: h0tl-supermarche-app
    kafka_topic: supermarche-homologation   # <dataset>-<namespace>
otel_edge_kubernetes_route:
  kafka_topic: homologation                 # <namespace>
```

Le rôle `otel_edge` refuse au déploiement un `kafka_topic` hors format
(`[a-z0-9_]` de part et d'autre du `-`), dupliqué, ou une route sans
`kubernetes_namespace`. Le job `otel-telemetry-topics` crée
`otel-{logs,metrics,traces}-supermarche-homologation` et
`otel-{logs,metrics,traces}-homologation` avec la rétention des topics de
base. Les collecteurs Kubernetes n'émettent que des métriques ; les topics de
logs et de traces de la route Kubernetes existent pour un receiver `filelog`
rétabli et pour éviter une création automatique sans rétention.

Exigence de sécurité validée (revue du backend, constat 4) : seule la table
de routage décide. Avant le routage, `transform/kafka-topic` supprime :

- `otel.kafka.topic`, `data_stream.namespace` et `apm.route.namespace` sur
  toute ressource reçue. Aucun client VM ne pose de namespace ;
- `data_stream.dataset` sur toute ressource routée ou qui porte
  `k8s.namespace.name`. Les agents EDOT des VM gardent leur
  `collectortelemetry`, posé sur leur télémétrie interne.

Limite : un client qui ne déclare ni `k8s.namespace.name` ni le marqueur
Kubernetes garde son `data_stream.dataset`. Rien ne le distingue d'un agent
VM, la clé Bearer n'identifiant pas le client. Son namespace étant supprimé,
il n'écrit que dans des data streams `*-default`.

Vérification du 2026-11-02 : un pod de `elastic-stack` a envoyé à l'Edge
trois logs avec `data_stream.namespace` = `pirate`. Ils sont arrivés dans
`logs-generic.otel-default` (namespace `elastic-stack` ou sans attribut
Kubernetes) et `logs-supermarche.otel-homologation` (namespace
`h0tl-supermarche-app`). Aucun data stream `*-pirate` n'a été créé ; les
trois documents de test ont été supprimés.

## Note du 2026-11-02 : plateforme et environnement posés par l'Edge

Pour les applications déployées, la plateforme et l'environnement ne sont
plus déclarés par l'application mais par sa route Edge :

```yaml
otel_edge_application_routes:
  - kubernetes_namespace: h0tl-supermarche-app
    kafka_topic: supermarche-homologation
    platform: k3s-01           # k8s.cluster.name
    environment: homologation  # deployment.environment.name
```

`transform/kafka-topic` pose les deux attributs, en écrasant la valeur reçue,
sur toute ressource dont `k8s.namespace.name` correspond à la route (logs,
métriques et traces). Les applications ne déclarent plus
`deployment.environment.name` dans `OTEL_RESOURCE_ATTRIBUTES`, et leurs
signaux portent désormais `k8s.cluster.name`, comme ceux des collecteurs
Kubernetes. Le rôle `otel_edge` refuse une route sans `platform` ni
`environment`, ou dont `environment` diffère du `<namespace>` du topic : le
data stream et l'attribut désignent le même environnement. Les ressources
hors route (VM, collecteurs) gardent leurs propres valeurs.
