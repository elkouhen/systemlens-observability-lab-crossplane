# ADR-002 : choisir la gestion EDOT standalone avec supervision Fleet

## Statut

Accepted. [ADR-006](ADR-006-collecteurs-opentelemetry-contrib.md) l'avait
amendé pour la distribution des collecteurs Kubernetes, Edge et backend ;
[ADR-014](ADR-014-retour-collecteurs-edot.md) les ramène sur EDOT

## Date

2026-09-25

## Contexte

Les VM exécutent un Elastic Agent en mode EDOT standalone. Sa configuration
locale décrit les receivers, le traitement des signaux et l'export OTLP vers
`otel-edge-01`. Fleet et OpAMP sont également disponibles sur `elk-01`, mais
ils peuvent soit gérer la collecte des agents, soit superviser des agents dont
la collecte reste déclarée localement.

Le dépôt utilise déjà Ansible comme source de vérité pour la configuration EDOT
des VM. Il doit éviter qu'une policy Fleet de collecte concurrente modifie ou
double le chemin `EDOT standalone → OTLP → otel-edge-01`. La configuration
standalone déclare aussi l'exporteur `otlphttp/edge` vers le Collecteur Edge et
l'utilise dans les pipelines de logs, métriques et traces. Cet exporteur est
nécessaire à l'acheminement des trois signaux vers la gateway OTLP.

## Décision

Les VM utilisent EDOT standalone pour la collecte et l'export des signaux. La
configuration est installée et maintenue par Ansible. Fleet utilise OpAMP pour
superviser ces agents, sans devenir la source de vérité de leur collecte.

Cette décision compare deux modes de gestion d'EDOT. Elle ne remet pas en
concurrence EDOT avec une autre distribution OpenTelemetry : le lab reste sur
la distribution Elastic, sélectionnée, testée et supportée par Elastic.

La séparation est donc la suivante :

| Responsabilité | Source de vérité |
| --- | --- |
| Receivers, processeurs et export OTLP des agents VM | Configuration EDOT versionnée et Ansible |
| État, identité et télémétrie interne des agents | OpAMP et Fleet |
| Assets Kibana et packages d'intégration | Fleet et les packages déclarés |

Les agents restent visibles dans Fleet comme collecteurs OTel supervisés. Ils
ne sont pas enrôlés comme agents Fleet classiques collecteurs. La cible
`make fleet-opamp-enable` active la supervision sans modifier le chemin de
données défini dans [ADR-001](ADR-001-choix-chemin-donnees-edot.md).

## Alternatives considérées

### Elastic Agent EDOT managé par Fleet

Fleet deviendrait la source de vérité de la collecte et distribuerait la
configuration des intégrations aux agents. Cette option centralise la gestion,
mais le mode Elastic Agent managé par Fleet et les intégrations retenues ici ne
permettent pas de déclarer l'exporteur OTLP personnalisé `otlphttp/edge` vers
`otel-edge-01`. Les logs, métriques et traces ne peuvent donc pas suivre le
chemin de données défini dans [ADR-001](ADR-001-choix-chemin-donnees-edot.md).
Cette option est écartée pour l'architecture de référence. Fleet peut
superviser un Collecteur OTel installé séparément avec OpAMP, mais ce mode ne
fait pas de Fleet la source de vérité de la collecte.

### EDOT standalone sans supervision OpAMP

Les agents conserveraient leur configuration locale sans rattachement à Fleet.
Cette option a été envisagée, mais elle ne permettrait pas de voir directement
l'état de l'agent dans Kibana. Elle est écartée pour le fonctionnement normal ;
elle reste un mode de repli si Fleet est temporairement indisponible.

## Conséquences

### Conséquences positives

- la configuration effective de la collecte reste versionnée dans le dépôt ;
- Fleet fournit une visibilité centralisée sans remplacer le chemin OTLP local ;
- une seconde exécution Ansible peut conserver un agent conforme et son
  identifiant OpAMP persistant ;
- les assets Kibana et la supervision Fleet restent disponibles pour le
  diagnostic.

### Coûts et limites

- la configuration est répartie entre Ansible pour la collecte et Fleet pour la
  supervision et les assets ;
- l'état Fleet peut être sain alors que le chemin EDOT vers Elasticsearch est
  interrompu, ou l'inverse ;
- le choix standalone est nécessaire pour conserver l'exporteur
  `otlphttp/edge` et l'acheminement des logs, métriques et traces vers
  `otel-edge-01` ;
- la recette doit contrôler séparément l'état OpAMP et la présence récente des
  logs, métriques et traces ;
- une modification durable de la collecte doit être faite dans Ansible, puis
  vérifiée sans activer une policy Fleet concurrente.

## Références

- [`ansible/README.md`](../ansible/README.md)
- [`ansible/roles/elastic_agent/templates/elastic-agent.yml.j2`](../ansible/roles/elastic_agent/templates/elastic-agent.yml.j2)
- [Elastic Agent comme Collecteur OpenTelemetry](https://www.elastic.co/docs/reference/fleet/elastic-agent-as-otel-collector)
- [Configurer un Elastic Agent standalone](https://www.elastic.co/docs/reference/fleet/configure-standalone-elastic-agents)
- [Intégrations OpenTelemetry avec Elastic Agent](https://www.elastic.co/docs/reference/fleet/otel-integrations)
- [Superviser les Collecteurs OpenTelemetry dans Fleet](https://www.elastic.co/docs/reference/fleet/monitor-otel-collectors)
- [Ajouter un Collecteur OpenTelemetry dans Fleet](https://www.elastic.co/docs/reference/fleet/add-otel-collector)
