# ADR-019 : la plateforme dans le namespace des data streams

## Statut

Accepted, déployé le 2026-11-08.

Depuis [ADR-020](ADR-020-plateforme-declaree-par-le-client.md), le backend
pose le namespace depuis `platform.id` et `deployment.environment.name`
déclarés par le client et contrôlés par l'Edge, sans lire le nom du topic,
et ne supprime plus les `data_stream.*` de record et de scope.

Remplace [ADR-010](ADR-010-dataset-application-namespace-environnement.md)
(le dataset nomme l'application, le namespace l'environnement) et la section « Plateforme : un champ,
pas un data stream » d'[ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md).
Conserve les topics par plateforme (ADR-015), les ACL Kafka (ADR-017) et l'indexation OTel native des
traces (ADR-018).

## Date

2026-11-08

## Contexte

Les data streams étaient nommés `<type>-<dataset>.otel-<environnement>`.
Toutes les plateformes d'un environnement partageaient donc les mêmes data
streams, par exemple `metrics-hostmetricsreceiver.otel-homologation` pour
`k3s`, `supermarche` et `elk`, distinguées par le seul champ `platform.id`.
Kibana ne pouvait séparer les plateformes que par un filtrage par document.

Un nommage `<type>-<plateforme>.otel-<environnement>` a été envisagé puis
écarté (voir alternatives) : les vues intégrées de Kibana sélectionnent les
données par leur dataset, valeur constante par data stream.

| Vue Kibana | Sélection |
| --- | --- |
| Infrastructure Hosts / Inventory | `data_stream.dataset: hostmetricsreceiver.otel` |
| Dashboards Fleet `[Kubernetes OTel]`, `[OTel] Host`, PostgreSQL OTel, MongoDB OTel | datasets des receivers (`kubeletstatsreceiver.otel`, `postgresqlreceiver.otel`…) |
| UI APM | `traces-*.otel-*`, `metrics-{service_transaction,…}.*.otel-*` |
| Fleet, collecteurs OpAMP | `metrics-collectortelemetry.otel-*` |

## Décision

```text
<type>-<dataset>.otel-<plateforme>_<environnement>
```

- Le dataset n'est jamais posé par la chaîne : celui du receiver
  (`hostmetricsreceiver`, `kubeletstatsreceiver`…), `generic` pour les
  signaux OTLP des applications (valeur par défaut de l'exporteur), et les
  datasets propres de `collectortelemetry` et du connecteur `elasticapm`.
  L'Edge ne porte plus de champ `dataset` dans `otel_edge_namespace_routes`.
- Une application n'a pas de dataset à son nom : la plateforme est déjà dans
  le namespace, et `logs-supermarche.otel-supermarche_homologation`
  répéterait la plateforme. Ses signaux vont dans
  `logs-generic.otel-supermarche_homologation`.
- Le collecteur backend pose `data_stream.namespace` =
  `<plateforme>_<environnement>`, lus dans le nom du topic
  `otel-<signal>-<plateforme>-<environnement>`, preuve de provenance
  (`transform/data-stream-route`). Sa télémétrie interne, qui ne passe pas
  par Kafka, porte `elk_homologation`.
- `deployment.environment.name` et `deployment.environment` restent
  l'environnement seul : `service.environment` = `homologation` pour l'UI
  APM.
- Les `data_stream.*` posés sur un log, un span, un point de métrique ou un
  scope sont supprimés par le backend : l'exporteur Elasticsearch les ferait
  primer sur ceux de la ressource, et un client pourrait changer de data
  stream.

| Plateforme | Exemples de data streams |
| --- | --- |
| `k3s` | `metrics-kubeletstatsreceiver.otel-k3s_homologation`, `metrics-k8sclusterreceiver.otel-k3s_homologation`, `metrics-hostmetricsreceiver.otel-k3s_homologation` |
| `supermarche` | `logs-generic.otel-supermarche_homologation`, `traces-generic.otel-supermarche_homologation`, `metrics-generic.otel-supermarche_homologation`, `metrics-service_transaction.1m.otel-supermarche_homologation`, `metrics-postgresqlreceiver.otel-supermarche_homologation` |
| `elk` | `metrics-hostmetricsreceiver.otel-elk_homologation`, `metrics-kafkametricsreceiver.otel-elk_homologation`, `metrics-collectortelemetry.otel-elk_homologation` |
| `demo` | `logs-generic.otel-demo_homologation`, `metrics-generic.otel-demo_homologation`, `traces-generic.otel-demo_homologation` |

## Alternatives considérées

- **`<type>-<plateforme>.otel-<environnement>`** : nom lisible, mais le
  dataset du receiver disparaît ; la vue Infrastructure Hosts/Inventory et
  les dashboards Fleet n'affichent plus rien, et la constance de
  `data_stream.dataset` par data stream interdit de le corriger par un alias
  ou un champ. Rejeté.
- **Dataset de l'application et namespace de plateforme** : nom redondant
  (`logs-supermarche.otel-supermarche_homologation`) et une règle de dataset
  à maintenir dans l'Edge. Rejeté.
- **Garder le namespace d'environnement et filtrer par document sur
  `platform.id`** : aucun renommage, mais la séparation repose sur des rôles
  à requête DLS, plus coûteux et plus fragiles qu'un motif d'index. Rejeté.

## Conséquences

- Chaque plateforme a ses propres data streams : privilèges d'index,
  rétention et data views par motif `*-*.otel-<plateforme>_*`, sans filtrage
  par document.
- Les vues intégrées de Kibana et de Fleet continuent de fonctionner : elles
  sélectionnent le dataset et lisent tous les namespaces.
- `logs-generic.otel-<plateforme>_<env>` reçoit aussi les logs fichiers
  (filelog) des VM de la plateforme, auxquels l'exporteur donne également
  `generic` : les requêtes applicatives filtrent par
  `resource.attributes.k8s.namespace.name` ou `service.name`.
- Le nom ne répète jamais la plateforme. Une application se distingue d'une
  autre de la même plateforme par `service.name`, comme dans l'UI APM.
- Les data streams `*.otel-homologation` existants ne reçoivent plus rien et
  expirent selon leur rétention ; les requêtes qui ciblaient un namespace
  exact doivent utiliser `*.otel-<plateforme>_<environnement>` ou
  `*.otel-*` filtré par `platform.id`.
- Les dashboards et scripts du dépôt qui lisaient `*-supermarche.otel-*`
  lisent `*-generic.otel-supermarche_*` (dashboard métier, SLO, contrôles).
- Fichiers concernés : `ansible/roles/otel_backend/templates/otel-backend.yaml.j2`,
  `ansible/roles/otel_edge/templates/otel-edge.yaml.j2`,
  `ansible/roles/otel_edge/tasks/routes.yml`,
  `ansible/inventory/group_vars/otel_edge_nodes.yml`,
  `platform/elk/dashboards/business-metrics*.{json,ndjson}`,
  `platform/elk/alerts/observability-policies.json`,
  `platform/elk/scripts/verify-{otel-routing,observability-contracts,dashboard-data}.sh`,
  `Makefile` (`demo-api-jvm-metrics-verify`), la documentation.

## Mise en œuvre

1. `make otel-config-validate` et `make ansible-validate`.
2. `make otel-backend-vm-provision` : les nouveaux data streams sont créés à
   la première écriture.
3. `make otel-edge-vm-provision` : l'Edge cesse de poser le dataset des
   applications.
4. Import du dashboard métier et des règles du dépôt, sur demande explicite.
5. Après 30 min sans écriture dans les anciens data streams
   `*-*.otel-<environnement>` : `make otel-legacy-datastreams-delete` liste
   ceux qui sont inactifs, `make otel-legacy-datastreams-delete CONFIRM=1`
   les supprime. Un data stream ayant reçu un document depuis
   `LEGACY_INACTIVE_WINDOW` (30m) est conservé.

## Vérification

```bash
make otel-routing-verify
make dashboards-verify kubernetes-otel-dashboards-verify postgresql-otel-dashboards-verify
make observability-schema-verify
```

`otel-routing-verify` attend, sur les quinze dernières minutes, des logs et
des métriques de chaque plateforme dans `*-*.otel-<plateforme>_homologation`,
les traces et les métriques APM agrégées de `supermarche` dans son
namespace, et aucun nouveau document dans `*-*.otel-homologation` ni
`*-*.otel-default`. Contrôle visuel : la vue Infrastructure Hosts liste les
cinq VM, et les dashboards `[Kubernetes OTel]` et `[OTel] Host` affichent des
données.
