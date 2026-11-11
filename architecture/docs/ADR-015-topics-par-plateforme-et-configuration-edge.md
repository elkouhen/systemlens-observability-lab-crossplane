# ADR-015 : un topic par plateforme, la configuration des plateformes portée par l'Edge

## Statut

Accepted, déployé le 2026-11-03 ([backlog](backlog.md)). Voir la note de mise
en œuvre et la vérification en fin de document.

La section « Plateforme : un champ, pas un data stream » est remplacée par
[ADR-019](ADR-019-namespace-par-plateforme.md) : le namespace des data
streams vaut `<plateforme>_<environnement>`.

La section « Configuration des plateformes portée par l'Edge » est remplacée
par [ADR-020](ADR-020-plateforme-declaree-par-le-client.md) : l'Edge ne
porte plus de table, chaque client déclare `platform.id` et
`deployment.environment.name`, et `otel_platforms` est dans
`group_vars/all.yml`. Les topics par plateforme et le backend générique
restent en vigueur.

Remplace la note du 2026-11-02 d'[ADR-007](ADR-007-namespace-data-stream-par-topic.md)
(le topic porte le dataset) et les règles de topic d'[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md)
(route Kubernetes, marqueur `otel.edge.source`). Conserve
[ADR-010](ADR-010-dataset-application-namespace-environnement.md) (le dataset
nomme l'application ou le receiver, le namespace nomme l'environnement) et son
mécanisme `apm.route.namespace`. Précise [ADR-005](ADR-005-signaux-backend-vers-kafka-local.md)
(topics cibles de l'agent de `otel-backend-01`).

## Date

2026-11-03

## Contexte

Le lab compte trois plateformes dans l'environnement `homologation` :

| Plateforme | Contenu | Chemin |
| --- | --- | --- |
| `k3s` | Cluster Kubernetes : collecteurs `otel-kubernetes*`, nœud `k3s-01` | Collecteur Edge `otel-edge-01` |
| `supermarche` | Namespace `h0tl-supermarche-app` et VM `supermarket-middleware-01` | Collecteur Edge `otel-edge-01` |
| `elk` | VM `elk-01`, `otel-edge-01`, `otel-backend-01`, collecteurs Edge et backend | Edge pour `elk-01` et `otel-edge-01` ; Kafka local pour `otel-backend-01` (ADR-005) |

Le modèle retenu : un cluster Kubernetes héberge n namespaces, un namespace
est une plateforme cliente dans un environnement donné, et le cluster comme ses
namespaces envoient leurs signaux au même collecteur Edge. Chaque VM déclare
sa plateforme, son environnement et l'Edge auquel elle envoie.

Aujourd'hui, le nom du topic porte toute la cible (`otel-<signal>-<dataset>-<namespace>`),
les signaux du cluster vont dans `otel-<signal>-homologation` par un marqueur
posé par les collecteurs, et les VM comme les collecteurs d'observabilité
vont dans les topics de base `otel-<signal>` sans plateforme ni environnement,
donc dans les data streams `*-default`. La plateforme n'apparaît ni dans
Kafka ni dans Elasticsearch, et le backend découpe le nom du topic pour
choisir le dataset, ce qui ne convient pas aux plateformes techniques dont
les dashboards Fleet lisent les datasets des receivers.

## Décision

### Topics Kafka : un jeu par plateforme et environnement

```text
otel-<signal>-<plateforme>-<environnement>    signal ∈ {logs, metrics, traces}
                                              plateforme, environnement ∈ [a-z0-9_]+
```

Neuf topics pour le lab : `otel-{logs,metrics,traces}-{k3s,supermarche,elk}-homologation`.
Les topics de base `otel-<signal>` et le topic `otel-<signal>-homologation`
disparaissent. La liste des plateformes est déclarée dans
`inventory/group_vars/otel_backend_nodes.yml` ; le rôle `otel_backend` crée
les topics avec trois partitions et la rétention actuelle, et échoue si une
table de l'Edge ou une VM référence une plateforme absente de la liste. Le
Job Kubernetes `otel-telemetry-topics` ne crée plus que les topics métier du
Kafka de `supermarket-middleware-01`.

```yaml
otel_platforms:
  - platform: k3s
    environment: homologation
  - platform: supermarche
    environment: homologation
  - platform: elk
    environment: homologation
```

### Déclaration par VM

Chaque VM déclare trois variables d'inventaire, au niveau du groupe ou de
l'hôte. Le rôle `elastic_agent` refuse une VM à laquelle il en manque une.

```yaml
otel_platform: supermarche
otel_environment: homologation
otel_edge: otel-edge-01          # ou kafka-local, réservé à otel-backend-01
```

| VM | `otel_platform` | `otel_edge` |
| --- | --- | --- |
| `k3s-01` | `k3s` | `otel-edge-01` |
| `supermarket-middleware-01` | `supermarche` | `otel-edge-01` |
| `elk-01` | `elk` | `otel-edge-01` |
| `otel-edge-01` | `elk` | `otel-edge-01` |
| `otel-backend-01` | `elk` | `kafka-local` |

Le rôle `elastic_agent` en tire l'endpoint OTLP et la clé de l'Edge déclaré,
ou, pour `kafka-local`, l'exporteur Kafka d'ADR-005 avec les topics
`otel-<signal>-<otel_platform>-<otel_environment>`. Une clé Edge par VM,
`OTEL_EDGE_KEY_<HOST>`, remplace les clés par type d'émetteur. `k3s-01`
reçoit un agent EDOT comme les autres VM ; le DaemonSet `otel-kubernetes`
cesse de collecter `hostmetrics`, qui serait en double, et garde
`kubeletstats`. Le Deployment `otel-kubernetes-cluster` ne change pas.

### Configuration des plateformes portée par l'Edge

L'Edge est associé à un cluster. Il porte deux tables et décide seul du topic
de chaque ressource ; les attributs de routage envoyés par un client sont
toujours supprimés.

- **Table des namespaces**, saisie dans `inventory/group_vars/otel_edge_nodes.yml`.
  Chaque entrée déclare la plateforme, l'environnement et le dataset :
  le nom de la plateforme pour une application, `receiver` pour une
  plateforme technique dont les dashboards lisent les datasets des receivers.

  ```yaml
  otel_edge_cluster_name: k3s-01      # k8s.cluster.name posé sur toute ressource du cluster
  otel_edge_namespace_routes:
    - kubernetes_namespace: h0tl-supermarche-app
      platform: supermarche
      environment: homologation
      dataset: supermarche
    - kubernetes_namespace: elastic-stack
      platform: k3s
      environment: homologation
      dataset: receiver
  ```

- **Table des hôtes**, rendue par Ansible depuis l'inventaire et non saisie :
  les hôtes dont `otel_edge` désigne cet Edge, avec leur plateforme et leur
  environnement. La VM déclare, l'Edge décide, les deux lisent l'inventaire.

Règles de `transform/kafka-topic`, dans l'ordre, pour chaque signal :

1. Supprimer `otel.kafka.topic`, `data_stream.namespace`, `apm.route.namespace`
   et `platform.id` reçus. Supprimer `data_stream.dataset` reçu, sauf la
   valeur `collectortelemetry` que les agents EDOT et les collecteurs posent
   sur leur télémétrie interne.
2. Ressource dont `k8s.namespace.name` figure dans la table des namespaces :
   topic `otel-<signal>-<platform>-<environment>`, `k8s.cluster.name` et
   `deployment.environment.name` posés en écrasant la valeur reçue. Si le
   dataset déclaré n'est pas `receiver`, `data_stream.dataset` est posé sur
   les logs et les métriques, jamais sur les traces (APM Server impose `apm`).
3. Sinon, ressource dont `host.name` figure dans la table des hôtes : topic
   `otel-<signal>-<platform>-<environment>` et `deployment.environment.name`
   posés. Le dataset reste celui du receiver.
4. Sinon, la ressource est rejetée par `filter/unrouted`. Le compteur
   `otelcol_processor_filter_*` de l'Edge rend l'oubli visible.

Le marqueur `otel.edge.source` des collecteurs Kubernetes et le processor
`resource/environment` disparaissent : le namespace `elastic-stack` suffit.
La télémétrie interne de l'Edge porte `host.name` dans
`service.telemetry.resource` et suit la règle 3.

### Backend générique

Le backend ne porte aucune table. Il souscrit à
`^otel-(logs|metrics|traces)-[a-z0-9_]+-[a-z0-9_]+$` et lit dans le nom du
topic, preuve de provenance, la plateforme et l'environnement :

| Signal | Posé depuis `otel-<signal>-<plateforme>-<env>` |
| --- | --- |
| Logs et métriques | `platform.id` = `<plateforme>`, `data_stream.namespace` = `<env>` ; le dataset reste celui posé par l'Edge ou dérivé du receiver |
| Traces | `platform.id` = `<plateforme>`, `data_stream.namespace` et `apm.route.namespace` = `<plateforme>_<env>` |

Le pipeline Elasticsearch `apm-route-namespace` d'ADR-010 ne change pas. La
télémétrie interne du backend, qui ne passe pas par Kafka, porte
`platform.id: elk` et `data_stream.namespace: homologation` dans
`service.telemetry.resource`.

### Plateforme : un champ, pas un data stream

La plateforme est le champ `platform.id` (`resource.attributes.platform.id`
sur les logs et métriques, label `platform_id` sur les données APM). Les
data streams restent nommés par dataset et environnement (ADR-010) :

| Plateforme | Data streams | Filtre Kibana |
| --- | --- | --- |
| `supermarche` | `logs-supermarche.otel-homologation`, `metrics-supermarche.otel-homologation`, `traces-apm-supermarche_homologation`, `logs-apm.error-supermarche_homologation`, `metrics-apm.*.1m-supermarche_homologation`, plus `metrics-{hostmetrics,mongodb,postgresql}receiver.otel-homologation` et `logs-*.otel-homologation` de la VM middleware | `platform.id: supermarche` |
| `k3s` | `metrics-{kubeletstats,k8scluster,prometheus,hostmetrics}receiver.otel-homologation`, logs système de `k3s-01` | `platform.id: k3s` |
| `elk` | `metrics-hostmetricsreceiver.otel-homologation`, `metrics-kafkametricsreceiver.otel-homologation`, `metrics-collectortelemetry.otel-homologation`, logs système | `platform.id: elk` |

Les noms des data streams applicatifs et Kubernetes ne changent pas. Les
signaux des VM et des collecteurs d'observabilité passent de `*-default` à
`*-homologation`.

## Alternatives considérées

- **Un listener OTLP par plateforme sur l'Edge** : une vraie association
  plateforme vers Edge sans règle sur les attributs, mais un port, une clé et
  un endpoint client par plateforme. Rejeté : le modèle retenu associe l'Edge
  au cluster, et le namespace Kubernetes identifie la plateforme.
- **Le dataset lu dans le topic** (ADR-007, note du 2026-11-02) : impose un
  dataset par plateforme, incompatible avec les datasets des receivers lus
  par les dashboards `[Kubernetes OTel]` et `[OTel] Host`.
- **Namespace `<plateforme>_<env>` pour tous les data streams** : un data
  stream par plateforme, rétention et data views dédiées, mais tous les noms
  changent et `logs-supermarche.otel-supermarche_homologation` répète la
  plateforme. Rejeté au profit du champ `platform.id`.
- **Namespace inconnu rangé dans la plateforme du cluster** : plus simple
  que le rejet, mais un oubli de déclaration polluerait `k3s` en
  `*-generic.otel-homologation`.
- **Un utilisateur SASL et une ACL par plateforme** : un seul Edge publie
  pour toutes les plateformes du cluster, l'ACL n'isolerait rien. Reporté.
- **Liste des plateformes dérivée de l'inventaire** : évite une liste au
  backend, mais le rendu croisé entre hôtes est moins lisible qu'une liste
  explicite contrôlée au déploiement.

## Conséquences

- Les topics croissent avec le nombre de plateformes et d'environnements,
  pas avec le nombre d'applications. Une nouvelle application dans un
  namespace existant ne crée rien dans Kafka.
- Une nouvelle plateforme : une entrée dans `otel_platforms`, une entrée
  dans la table des namespaces de l'Edge ou les trois variables de ses VM,
  puis `make otel-backend-vm-provision` et le provisionnement de l'Edge et
  des agents.
- Le backend fait confiance aux attributs de data stream posés par l'Edge,
  parce que seul l'Edge, authentifié auprès de Kafka, publie dans les topics
  et qu'il supprime ceux des clients. Un client qui ne déclare ni
  `k8s.namespace.name` connu ni `host.name` connu est rejeté ; un client qui
  usurpe un `host.name` connu rejoint la plateforme de cet hôte, limite du
  même ordre que l'usurpation de `k8s.namespace.name` aujourd'hui.
- Une ressource rejetée par l'Edge est perdue. Le compteur du processor
  `filter` et la cible `make otel-routing-verify` ci-dessous rendent la
  perte visible.
- Les métriques `hostmetrics` de `k3s-01` viennent de l'agent EDOT de la VM
  et non plus du DaemonSet ; même dataset, même dashboard.
- `otel-backend-01` reste l'exception d'ADR-005, déclarée par
  `otel_edge: kafka-local`.
- Documents à mettre à jour avec la mise en œuvre : `docs/architecture.md`,
  `docs/briques-remontee-telemetrie.md`, `architecture/ansible/README.md`,
  `apps/ADDING_APPLICATION.md`, le README du rôle `elastic_agent`.

## Mise en œuvre et migration

Fichiers concernés :

- `architecture/ansible/inventory/group_vars/*.yml` : variables `otel_platform`,
  `otel_environment`, `otel_edge` par groupe ; `otel_platforms` au backend ;
  `otel_edge_cluster_name` et `otel_edge_namespace_routes` à l'Edge ; clés
  `OTEL_EDGE_KEY_<HOST>` dans `all.yml`.
- `architecture/ansible/roles/otel_edge/` : tables, règles 1 à 4,
  `filter/unrouted`, télémétrie interne avec `host.name`.
- `architecture/ansible/roles/otel_backend/` : création des topics depuis
  `otel_platforms`, souscription stricte, `transform/data-stream-route` sur
  plateforme et environnement, télémétrie interne avec `platform.id`.
- `architecture/ansible/roles/elastic_agent/` : endpoint et clé depuis
  `otel_edge`, topics de `kafka/backend` depuis la plateforme, agent sur
  `k3s-01`.
- `architecture/platform/kubernetes/base/observability/otel-kafka.yaml` :
  retrait de `hostmetrics`, de `resource/edge-source` et de
  `resource/environment` ; Job limité aux topics métier.
- `Makefile` : cible `otel-routing-verify`.

Ordre de migration, sans perte :

1. `make otel-backend-vm-provision` : création des neuf topics, nouveau
   routage, souscription transitoire qui ajoute `^otel-(logs|metrics|traces)(-homologation)?$`.
   Ces topics ne posent rien et continuent d'écrire comme avant, les
   signaux routés `supermarche-homologation` sont lus par la règle nouvelle
   avec le même résultat.
2. `make otel-edge-vm-provision`, `make elastic-agent-vm-provision`,
   `make kubernetes-observability-deploy` : les producteurs basculent sur
   les topics par plateforme.
3. Lag nul du groupe `otel-backend` sur les six anciens topics, suppression
   de ces topics, retrait de la souscription transitoire et nouveau
   `make otel-backend-vm-provision`.

## Vérification

```bash
make kubernetes-validate
make ansible-validate
make otel-config-validate
make otel-validation
make otel-routing-verify
make trace-context-verify observability-schema-verify dashboards-verify kubernetes-otel-dashboards-verify
```

`otel-config-validate` rend les configurations Edge, backend et agents depuis
l'inventaire (`ansible/render-otel-configs.yml`) et les valide avec le
binaire EDOT de la version de la stack.

`otel-routing-verify` contrôle, sur les quinze dernières minutes : des
documents portant `platform.id` égal à chacune des plateformes de
`otel_platforms` dans `logs-*` et `metrics-*`, des traces dans
`traces-apm-supermarche_homologation` avec le label `platform_id` retiré,
aucun nouveau document dans `*-default`, aucun document portant
`otel.kafka.topic`, et un compteur `otelcol_processor_filter_*` de l'Edge
nul. Le test d'ADR-009 est rejoué : trois logs envoyés depuis un pod de
`elastic-stack` avec `data_stream.namespace` = `pirate` et `platform.id` =
`pirate` arrivent dans `*-homologation` avec `platform.id` = `k3s`, et un
log envoyé avec un `k8s.namespace.name` inconnu est rejeté par l'Edge.

## Note de mise en œuvre du 2026-11-03

Écarts avec la décision, constatés à l'implémentation :

- **Le marqueur `otel.edge.source=kubernetes` est conservé.** Les métriques
  `kubeletstats` d'un pod applicatif portent le `k8s.namespace.name` du pod :
  sans marqueur, elles iraient dans la plateforme de l'application avec son
  dataset. Comme dans ADR-009, les métriques et les traces marquées suivent
  leur émetteur, avant la règle des namespaces ; les logs suivent le namespace
  de leur pod, le marqueur passe après. Le marqueur reste supprimé avant
  l'indexation.
- **Forme des tables de l'Edge.** `otel_edge_cluster` (`name`,
  `kubernetes_namespace`, `platform`, `environment`) décrit le cluster et le
  namespace de ses collecteurs ; `otel_edge_namespace_routes` les plateformes
  hébergées. `deployment.environment.name` suit le topic choisi, ce qui
  couvre les namespaces, le marqueur et les VM d'une seule règle.
- **`host.name` sur la télémétrie interne des agents EDOT** des VM, comme
  sur celle de l'Edge, pour qu'elle soit routée par la table des VM.
- **Souscription transitoire** portée par `otel_backend_legacy_topics`
  (`inventory/group_vars/otel_backend_nodes.yml`) : le backend lit encore
  `otel-<signal>` et `otel-<signal>-homologation` avec leur ancienne
  sémantique. Le topic `otel-<signal>-supermarche-homologation` garde son nom.
- **Validation hors VM** : `make otel-config-validate` rend et valide les
  sept configurations ; la cohérence des plateformes entre l'inventaire, les
  tables de l'Edge et `otel_platforms` est vérifiée par
  `roles/otel_backend/tasks/platforms.yml` et `roles/otel_edge/tasks/routes.yml`.
- **Playbook `validation/otel`** : la métrique de validation porte
  `host.name` = `otel-edge-01` et arrive dans
  `metrics-generic.otel-homologation` avec `platform.id` = `elk`.

## Vérification du 2026-11-03

Migration en trois étapes : `make otel-backend-vm-provision` (neuf topics
créés, souscription transitoire), `make otel-edge-vm-provision`,
`make elastic-agent-vm-provision` et `make kubernetes-observability-deploy`
(bascule des producteurs, agent EDOT installé sur `k3s-01`), puis
`otel_backend_legacy_topics: false` et nouveau provisionnement du backend
après lag nul sur les six anciens topics.

- `make otel-config-validate`, `make kubernetes-validate` et
  `make ansible-validate` réussissent.
- `make otel-routing-verify` réussit : logs et métriques de `k3s`,
  `supermarche` et `elk` avec `platform.id`, traces dans
  `traces-apm-supermarche_homologation` sans label indexé, aucun document
  OTel récent en `default`, aucun `otel.kafka.topic` indexé, aucun rejet.
- `make otel-validation`, `make trace-context-verify`,
  `make observability-schema-verify`, `make dashboards-verify` et
  `make kubernetes-otel-dashboards-verify` réussissent.
- Test d'usurpation : un log envoyé depuis `elastic-stack` avec
  `data_stream.namespace`, `data_stream.dataset` et `platform.id` à `pirate`
  est arrivé dans `logs-generic.otel-homologation` avec `platform.id` = `k3s`
  et `k8s.cluster.name` = `k3s-01` ; un log avec un `k8s.namespace.name`
  inconnu a été rejeté et `otelcol_processor_filter_logs.filtered` est passé
  à 1. Les documents de test ont été supprimés.
- Les noms des data streams applicatifs et Kubernetes n'ont pas changé ; les
  signaux des VM et des collecteurs sont passés de `*-default` à
  `*-homologation`. Les quatorze data streams `*-default` OTel et APM
  devenus inactifs ont été supprimés, puis, à la demande de l'utilisateur,
  tous les data streams `logs-*`, `metrics-*` et `traces-*` pour repartir
  de documents portant tous `platform.id` ; dix-neuf flux se sont recréés
  en trois minutes, sans document en `default` ni attribut manquant.

Deux corrections ont été nécessaires pendant la migration : l'adresse de
l'Edge dans les agents est `hostvars[otel_edge].ansible_host`, car `node_ip`
est une extra var globale du provisionnement ; et pendant la fenêtre transitoire, la
règle de dataset de l'ancien topic `supermarche-homologation` s'appliquait
aussi aux signaux de la VM `supermarket-middleware-01`, dont 1861 documents
ont été retirés des flux applicatifs.

Reste à faire par un opérateur : supprimer les six anciens topics vidés
(`otel-{logs,metrics,traces}` et `otel-{logs,metrics,traces}-homologation`)
avec `kafka-topics.sh --delete` sur `otel-backend-01`.

## Note du 2026-11-08 : simplification des collecteurs

- La souscription transitoire et `otel_backend_legacy_topics` sont retirées :
  les six anciens topics sont supprimés depuis la migration.
- `deployment.environment.name` n'est plus posé par l'Edge mais par le
  backend, depuis le topic, comme `platform.id` et `data_stream.namespace`.
  Une seule règle couvre ainsi les ressources routées par l'Edge et l'agent
  EDOT qui publie directement dans Kafka (`otel_edge: kafka-local`).
- `transform/data-stream-route` applique la même règle aux trois signaux ;
  la composition `<plateforme>_<environnement>` et `apm.route.namespace`
  sont posées par `transform/apm-route`, partagé par les traces et les
  métriques de l'agent Java OTel (ADR-016).
