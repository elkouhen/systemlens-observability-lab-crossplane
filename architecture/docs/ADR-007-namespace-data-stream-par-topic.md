# ADR-007 : choisir le namespace des data streams par topic Kafka

## Statut

Accepted, remplacé pour la forme du topic par
[ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md) : le topic
porte la plateforme et l'environnement, `otel-<signal>-<plateforme>-<env>`,
et le dataset est posé par l'Edge.

Amendé le 2026-11-02 par
[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md) : le collecteur Edge
publie aussi dans des topics suffixés, et les topics `otel-<signal>-supermarche`
et `otel-<signal>-k8s` sont créés avec la rétention des topics de base.

Amendé le 2026-11-02 par
[ADR-010](ADR-010-dataset-application-namespace-environnement.md) : le
suffixe du topic ne fixe plus le namespace. Il isole un flux routé et indique
au backend de poser `data_stream.namespace` depuis l'environnement de la
ressource (`deployment.environment.name`, sinon `deployment.environment`,
sinon `default`). Un producteur qui publie dans `otel-*-recette` écrit donc
dans `<type>-<dataset>-<environnement>`. Les topics de base ne changent pas.

Amendé le 2026-11-02 par la note du même jour en fin de document : le nom du
topic porte de nouveau toute la cible, dataset compris
(`otel-<signal>-<dataset>-<namespace>`). Le backend ne lit plus
l'environnement de la ressource. Cette note remplace l'amendement d'ADR-010
ci-dessus.

## Date

2026-11-02

## Contexte

Les signaux transitent par le Kafka OTel avant d'être écrits par le collecteur
backend. L'exporteur Elasticsearch route chaque document vers
`<type>-<data_stream.dataset>-<data_stream.namespace>` ; sans attribut, le
dataset vient du receiver d'origine (ou `generic`) et le namespace vaut
`default`. Les traces passent par APM Server, qui écrit dans
`traces-apm-<namespace>`.

Le besoin est de contrôler le data stream cible des logs, métriques et traces
sans modifier chaque source, en s'appuyant sur la souscription par regex du
backend ([ADR-006](ADR-006-collecteurs-opentelemetry-contrib.md)).

## Décision

Le suffixe du topic détermine le namespace : `otel-<signal>-<namespace>`.

- Le receiver Kafka expose le topic d'origine dans le contexte (`kafka.topic`).
  Le processor `resource/kafka-topic` le copie en attribut de ressource avant
  le batch ; `transform/data-stream-namespace` en déduit
  `data_stream.namespace`, normalisé en `[a-z0-9_]` minuscules, puis supprime
  l'attribut technique.
- Les topics de base (`otel-logs`, `otel-metrics`, `otel-traces`) ne posent
  aucun namespace : le comportement existant est conservé.
- Le topic ne choisit que le namespace. Le dataset reste choisi par la source,
  car il peut contenir des points (`hostmetricsreceiver.otel`) et rendrait le
  nom de topic ambigu.
- APM Server respecte l'attribut de ressource `data_stream.namespace` : les
  traces conservent l'UI APM complète.

## Alternatives considérées

- **Table de règles dans le backend** (par `service.name`, namespace
  Kubernetes…) : centralisée mais ne sépare pas les flux dans Kafka.
- **Attributs posés à la source** : déjà supportés par l'exporteur, mais la
  règle est dispersée dans chaque application ou collecteur.

## Conséquences

- Un flux dédié est isolé dans Kafka (topic propre) et dans Elasticsearch
  (data stream propre, mêmes templates et politiques que le namespace
  `default`).
- Le collecteur Edge publie uniquement dans les topics de base. Un producteur
  qui cible un namespace publie directement dans le Kafka OTel. *Amendé par
  ADR-009 : l'Edge choisit lui-même un topic suffixé pour les signaux
  applicatifs et Kubernetes.*
- Les topics suffixés sont créés automatiquement par le broker et ne reçoivent
  pas la rétention appliquée par le job `otel-telemetry-topics` aux topics de
  base.

## Vérification

Un log, une métrique et une trace publiés dans `otel-*-recette` ont été écrits
dans `logs-generic-recette`, `metrics-generic.otel-recette` et
`traces-apm-recette`, tandis que le trafic des topics de base restait dans le
namespace `default`.

## Note du 2026-11-02 : le topic porte le dataset et le namespace

Décision produit : le collecteur backend reste le composant qui lit les
topics par regex et range chaque flux dans son data stream. Le nom du topic
porte toute la cible, sans attribut de ressource ni règle d'environnement.

| Topic | Logs et métriques | Traces (APM Server) |
| --- | --- | --- |
| `otel-<signal>-<dataset>-<namespace>` | `data_stream.dataset` = `<dataset>`, `data_stream.namespace` = `<namespace>` | `data_stream.namespace` et `apm.route.namespace` = `<dataset>_<namespace>` |
| `otel-<signal>-<namespace>` | `data_stream.namespace` = `<namespace>`, dataset de la source ou du receiver | `data_stream.namespace` = `<namespace>` |
| `otel-<signal>` (topic de base) | rien | rien |

- `resource/kafka-topic` copie le topic lu (`metadata.kafka.topic`) en
  attribut de ressource. `transform/data-stream-route` le découpe par
  `ExtractPatterns`, pose les attributs du tableau puis supprime
  `otel.kafka.topic`. Il supprime aussi tout `apm.route.namespace` reçu sur
  une trace : seul le backend le pose.
- Le backend ne lit plus `deployment.environment(.name)` et ne normalise plus
  rien à l'exécution. Le format du topic contraint les noms : dataset
  `[a-z0-9_.]` sans `-`, namespace `[a-z0-9_]`. Un topic hors de ces formes
  ne pose rien.
- Le collecteur Edge choisit seulement le topic, depuis sa table de routage
  ([ADR-009](ADR-009-namespaces-supermarche-et-k8s.md), note du 2026-11-02).
  Il supprime d'abord les attributs de routage fournis par le client.
- Le mécanisme `apm.route.namespace` → label `apm_route_namespace` →
  pipeline Elasticsearch `apm-route-namespace` d'ADR-010 ne change pas.

Les topics `otel-<signal>-supermarche` et `otel-<signal>-k8s` sont remplacés
par `otel-<signal>-supermarche-homologation` et `otel-<signal>-homologation`.
Les noms des data streams ne changent pas.

Alternatives écartées :

- **Table de routage statique à l'Edge posant les attributs** : une seule
  source de vérité aussi, mais le backend ne serait plus le composant qui
  route. Les topics ne diraient plus où vont leurs messages.
- **Namespace tiré de l'environnement de la ressource** (amendement
  d'ADR-010) : chaîne de repli, normalisation et `Concat` dans le backend,
  pour une valeur que la route connaît déjà.

Conséquences :

- Une route Edge vise un seul couple dataset et environnement. Un second
  environnement de la même application demande une seconde route et ses
  trois topics.
- Un producteur qui publie directement dans le Kafka OTel choisit sa cible
  par le nom du topic : `otel-logs-recette` écrit dans
  `logs-<dataset de la source>-recette`, `otel-logs-equipe-a` dans
  `logs-equipe.otel-a`.
- Le nom du topic est un contrat : renommer une route renomme ses topics.

Vérification du 2026-11-02 : après création des topics, provisionnement de
l'Edge et du backend et suppression des six anciens topics (lag nul), les
data streams reçoivent les mêmes noms qu'avant. Aucun data stream n'a été
créé. Les quatre contrôles `*-verify` réussissent.
