# ADR-020 : la plateforme déclarée par le client, l'Edge contrôle

## Statut

Accepted, 2026-11-09. Voir la section Vérification en fin de document.

Remplace la section « Configuration des plateformes portée par l'Edge »
d'[ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md) et les
règles de priorité d'[ADR-009](ADR-009-namespaces-supermarche-et-k8s.md)
(marqueur `otel.edge.source`, namespace Kubernetes, `host.name`). Conserve les
topics par plateforme (ADR-015), le backend générique qui lit le topic
(ADR-015, ADR-019), les ACL Kafka (ADR-017) et le registre `otel_platforms`.

## Date

2026-11-09

## Contexte

Depuis ADR-015, l'Edge décide seul du topic de chaque ressource depuis trois
clés : le marqueur `otel.edge.source=kubernetes` des collecteurs Kubernetes,
le namespace Kubernetes (`k8s.namespace.name`) et le nom de la VM
(`host.name`). Trois tables, dans trois endroits (group_vars de l'Edge,
inventaire des VM, `routes.yml`), un macro Jinja qui rend trois blocs OTTL
quasi identiques, et un ordre des règles qui diffère entre les logs et les
métriques. Le rendu compte douze statements par signal pour quatre
plateformes, et une dépendance d'ordre invisible : les pods applicatifs
portent `host.name` = `k3s-01`, VM elle-même rattachée à l'Edge, et ne vont
dans `supermarche` que parce que la règle du namespace passe avant celle de
l'hôte.

La justification de cette complexité était qu'un client ne choisit jamais
son topic. Cette garantie n'existe pas : les trois clés de routage sont des
attributs de ressource posés par le client lui-même. Un agent qui envoie
`host.name` = `elk-01` ou `otel.edge.source` = `kubernetes` rejoint la
plateforme correspondante. La table n'apporte donc aucune protection par
rapport à un client qui déclarerait directement sa plateforme.

## Décision

Chaque client déclare sa plateforme et son environnement dans sa ressource,
par les deux attributs déjà indexés :

| Attribut | Valeur |
| --- | --- |
| `platform.id` | plateforme, `[a-z0-9_]+` |
| `deployment.environment.name` | environnement, `[a-z0-9_]+` |

L'Edge ne porte plus de table. Pour chaque signal, `transform/kafka-topic`
pose `otel.kafka.topic` = `otel-<signal>-<platform.id>-<deployment.environment.name>`
si le couple figure parmi les plateformes qui lui sont attribuées dans le
registre `otel_platforms` (entrées dont il est `publisher`). Sinon, la
ressource n'a pas de topic et `filter/unrouted` la rejette, comptée par
`otelcol_processor_filter_*`. L'Edge ne touche à aucun autre attribut : un
seul processor `batch` pour les trois signaux, plus de suppression de
`data_stream.dataset` ni de `k8s.cluster.name` posé.

Le registre `otel_platforms` passe de `group_vars/otel_backend_nodes.yml` à
`group_vars/all.yml` : il est lu par le backend (topics, comptes, ACL) et par
l'Edge (plateformes servies).

Le backend ne lit plus le nom du topic. Les attributs déclarés sont la
source : `transform/data-stream-namespace` pose
`data_stream.namespace` = `<platform.id>_<deployment.environment.name>` et
`deployment.environment` (cible de l'alias `service.environment` des
templates OTel d'Elasticsearch, vérifié sur la stack 9.5.4 :
`semconv-resource-to-ecs@mappings`), puis supprime `otel.kafka.topic`. Les
processors `resource/kafka-topic` et `transform/data-stream-route`
(`ExtractPatterns`) disparaissent, comme la suppression des `data_stream.*`
de record et de scope (ADR-019) : aucun producteur n'en pose, et le modèle
est désormais que le client déclare. Une ressource sans les deux attributs
irait en namespace `default`, ce que `make otel-routing-verify` détecte ;
elle n'atteint pas Kafka, l'Edge la rejette avant. La télémétrie interne du
backend passe par le même processor.

Où chaque client déclare sa plateforme :

| Client | Déclaration |
| --- | --- |
| Agent EDOT d'une VM | `resource/agent` et `service.telemetry.resource`, depuis `otel_platform` et `otel_environment` de l'inventaire |
| Collecteurs `otel-kubernetes` et `otel-kubernetes-cluster` | processor `resource/platform` (`k3s`, `homologation`), à la place du marqueur `otel.edge.source` |
| Pod applicatif | `OTEL_RESOURCE_ATTRIBUTES` posé par l’Application Crossplane, avec `k8s.cluster.name` que l'Edge posait |
| Télémétrie interne de l'Edge | `service.telemetry.resource`, depuis `otel_platform` et `otel_environment` |
| Playbook `validation/otel` | attribut `platform.id` de la métrique |

Contrôles au rendu (`make otel-config-validate`) et au provisionnement :

- `roles/otel_edge/tasks/platforms.yml` : l'Edge est `publisher` d'au moins
  une plateforme, et chaque VM rattachée (`otel_edge`) déclare une plateforme
  servie par cet Edge ;
- `roles/otel_backend/tasks/inventory-check.yml` : la plateforme de chaque VM
  est au registre, avec son Edge, ou la VM en `kafka-local`, parmi ses
  `publishers`.

Un namespace Kubernetes n'est plus déclaré nulle part côté Ansible : une
nouvelle application déclare sa plateforme dans son patch, et la plateforme
doit exister au registre avec l'Edge en `publisher`.

## Alternatives écartées

- **Conserver les tables en aplatissant le template** : réduit le Jinja mais
  garde trois clés de routage, l'ordre des règles et la dépendance d'ordre
  entre `k8s.namespace.name` et `host.name`, pour une garantie qui n'existe
  pas.
- **Identifier le client par sa clé Bearer** : l'extension
  `bearertokenauth` n'expose pas l'identité du jeton aux processors OTTL.
- **Un port d'écoute par plateforme** : multiplie les frontends HAProxy et
  les secrets pour le même résultat.

## Conséquences

- Le rendu de l'Edge passe de douze statements par signal à trois, sans
  macro ; une plateforme de plus n'ajoute qu'une alternative à la regex.
- `group_vars/otel_edge_nodes.yml` ne porte plus que les trois variables
  communes à toute VM.
- Un client qui déclare une plateforme servie y est accepté, comme il
  l'était en usurpant `host.name`. Un client sans déclaration, ou avec une
  plateforme non attribuée à l'Edge, est rejeté.
- Les pods applicatifs déclarent trois attributs de plus ; l'Edge ne pose
  plus `k8s.cluster.name`.
- Les documents indexés ne changent pas : mêmes data streams, mêmes valeurs
  de `platform.id`, `deployment.environment.name`, `deployment.environment`
  et `k8s.cluster.name`.
- Le backend ne contient plus de règle héritée des routages précédents
  (ADR-007, ADR-009, ADR-010, ADR-015) : un processor de namespace, le
  filtre des NaN, `cumulative_to_delta` et `elasticapm`.

## Mise en œuvre

- `architecture/ansible/inventory/group_vars/all.yml` : `otel_platforms` ;
  `otel_backend_nodes.yml` et `otel_edge_nodes.yml` allégés.
- `architecture/ansible/roles/otel_edge/` : `tasks/platforms.yml` remplace
  `tasks/routes.yml` ; `templates/otel-edge.yaml.j2` sans tables.
- `architecture/ansible/roles/otel_backend/tasks/inventory-check.yml` :
  contrôle limité aux VM.
- `architecture/ansible/roles/otel_backend/templates/otel-backend.yaml.j2` :
  `transform/data-stream-namespace` depuis les attributs déclarés.
- `architecture/ansible/roles/elastic_agent/templates/elastic-agent.yml.j2` :
  `platform.id` sur `resource/agent` et la télémétrie interne.
- `architecture/gitops/otel-pipeline/kubernetes-collectors.yaml` :
  `resource/platform` à la place de `resource/edge-source`.
- `architecture/gitops/*/application*.yaml` (`spec.otel`) : `platform.id`,
  `deployment.environment.name`, `k8s.cluster.name`.
- `validation/otel/` : `platform.id` sur la métrique de validation.

Déploiement, sans perte : `make otel-edge-vm-provision` d'abord ne suffit
pas, car les producteurs ne déclarent pas encore leur plateforme et seraient
rejetés. Ordre retenu : `make elastic-agent-vm-provision`,
`make apps-deploy` et `make demo-api-deploy` (les producteurs déclarent,
l'Edge actuel ignore ces attributs et route encore par ses tables), puis
`make otel-edge-vm-provision`, `make kubernetes-observability-deploy` et
enfin `make otel-backend-vm-provision`, une fois l'Edge en place pour que
tout message consommé porte les attributs.

## Vérification

```bash
make ansible-validate
make otel-config-validate
make kubernetes-validate
make otel-routing-verify
make otel-validation
```

`otel-config-validate` rend et valide les sept configurations ; une VM dont
la plateforme n'est pas servie par son Edge, ou absente du registre, fait
échouer le rendu (vérifié avec `-e otel_platform=inconnue`).
`otel-routing-verify` contrôle, sur les quinze dernières minutes, des
documents portant `platform.id` pour chaque plateforme du registre, aucun
document sans plateforme et un compteur `otelcol_processor_filter_*` de
l'Edge nul.

### Vérification du 2026-11-09

Déploiement dans l'ordre ci-dessus : agents EDOT de `k3s-01`,
`supermarket-middleware-01` et `elk-01`, applications, Edge, collecteurs
Kubernetes, backend. Résultats :

- `make otel-config-validate` : sept configurations valides.
- `make otel-routing-verify` sur cinq minutes, hors fenêtre de bascule :
  réussi. Les quatre plateformes reçoivent logs et métriques avec
  `platform.id`, aucun document sans plateforme, aucun `otel.kafka.topic`
  indexé, compteur de rejet de l'Edge nul.
- `make otel-validation` : la métrique de validation arrive dans
  `metrics-generic.otel-elk_homologation` avec `platform.id` = `elk` et
  `deployment.environment` = `homologation`.
- `make trace-context-verify`, `make observability-schema-verify`,
  `make kubernetes-otel-dashboards-verify` : réussis.
- Pendant la bascule, des signaux d'agents EDOT ont été indexés en
  namespace `default` et l'Edge a rejeté quelques points, le temps que
  l'agent de `otel-edge-01` et le backend soient reprovisionnés. Plus rien
  après la bascule.
- `make dashboards-verify` échoue sur une requête ES|QL du dashboard métier :
  `metrics.jvm.memory.used` est `long` dans l'index du 2026-11-08 et
  `double` dans celui du 2026-11-09 06:34, créé avant ce déploiement. Écart
  préexistant, indépendant d'ADR-020. Résolu le même jour en supprimant les
  97 data streams `logs-*`, `metrics-*` et `traces-*`, dont les restes
  d'APM Server, recréés par les écritures suivantes ; les index système
  (Kibana, Fleet, sécurité) sont conservés. `make dashboards-verify`,
  `make otel-routing-verify`, `make kubernetes-otel-dashboards-verify` et
  `make trace-context-verify` réussissent ensuite.
