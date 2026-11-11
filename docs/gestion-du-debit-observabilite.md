# Gestion du débit de télémétrie

Ce guide décrit les mécanismes disponibles pour maîtriser le débit des traces,
logs et métriques de l’architecture active. Les valeurs sont des points de
départ : elles doivent être ajustées à partir du volume observé, de la taille
des événements et de la capacité d’indexation Elasticsearch.

## Mécanismes disponibles

| Mécanisme | Fonction |
| --- | --- |
| Rate limiting | Refuser ou ralentir un débit entrant au-delà d’un seuil |
| Sampling et filtrage | Réduire volontairement le volume conservé |
| Batch | Regrouper les événements pour réduire le coût réseau et Elasticsearch |
| Backpressure | Ralentir la source lorsque le consommateur est saturé |
| Queue et buffer | Absorber une indisponibilité ou un pic temporaire |
| `memory_limiter` | Protéger un Collector contre l’épuisement mémoire |

## Stratégie commune

Le contrôle du débit suit ce chemin :

```text
Entrée réseau -> limite par source -> réduction par signal -> batch
-> queue et backpressure -> indexation Elasticsearch
```

Définir un budget par signal et mesurer ce budget après enrichissement :

| Signal | Budget à définir | Réaction au dépassement |
| --- | --- | --- |
| Traces | spans par seconde et par service | sampling, puis limitation au Collecteur Edge |
| Logs | événements par seconde et par namespace ou VM | filtrage des logs verbeux, puis ralentissement |
| Métriques | séries actives et points par seconde | augmenter l’intervalle ou désactiver une famille |

## Traces applicatives

```text
Agent Java OpenTelemetry -> Collecteur Edge -> Kafka otel-traces
-> Collector backend -> Elasticsearch
```

- Appliquer le sampling dans l’agent ou au Collecteur Edge.
- Conserver une priorité plus élevée pour les erreurs et les transactions
  lentes afin de préserver leur valeur de diagnostic.
- Compléter toute limite réseau par le sampling, car une requête OTLP peut
  contenir un nombre variable de spans.
- Conserver `memory_limiter` et `batch` dans le Collecteur Edge et le Collector
  backend.
- Surveiller le débit des topics `otel-traces-*`, le consumer lag et les erreurs
  d’export.

## Logs applicatifs

```text
Logback -> agent Java OTel (OTLP) -> Edge -> Kafka otel-logs-supermarche-homologation
-> Collector backend -> Elasticsearch
```

- Régler le niveau de logs applicatif à `INFO` par défaut : l'agent exporte
  ce que Logback émet, selon les niveaux de Spring Boot.
- Activer `DEBUG` temporairement et par service lorsque le diagnostic le
  justifie.
- Filtrer les logs répétitifs dans le pipeline du collecteur Edge ou backend
  avant l’indexation.
- Régler `batch`, `memory_limiter` et la queue du Collector backend.
- Surveiller le débit des topics `otel-logs-*`, le consumer lag et les rejets du
  backend.

Les logs VM suivent le même chemin Edge et Kafka avec Elastic Agent EDOT
standalone. Ils sont publiés dans `otel-logs-<plateforme>-<environnement>`.

## Métriques applicatives et Kubernetes

```text
Micrometer OTLP et collecteurs EDOT -> Collecteur Edge -> Kafka otel-metrics
-> Collector backend -> Elasticsearch
```

Les métriques applicatives sont scrappées toutes les 15 secondes sur les
endpoints `/actuator/prometheus`. Les métriques Kubernetes sont collectées par
les composants EDOT prévus dans les manifests.

- Utiliser `collection_interval` pour les métriques hôte et techniques.
- Réduire la cardinalité avant Kafka avec les processeurs OTel `filter` ou
  `transform`, en conservant les champs utilisés par Kibana.
- Dimensionner les topics `otel-metrics-*` à partir du nombre de séries actives et
  non du seul nombre de messages.
- Conserver `batch` et `memory_limiter` sur les étages de collecte et de
  traitement.
- Surveiller le consumer lag Kafka comme signal de saturation du chemin.

## Logs et métriques des VM

```text
Elastic Agent EDOT standalone -> Collecteur Edge -> Kafka -> Collector backend
-> Elasticsearch
```

- Régler les périodes des receivers System, Kafka, MongoDB et PostgreSQL dans
  la configuration EDOT standalone versionnée sous
  `architecture/ansible/roles/elastic_agent/`.
- Désactiver les inputs non nécessaires et limiter les chemins de logs suivis.
- Utiliser les processeurs de la policy pour supprimer les événements
  répétitifs avant indexation.
- Conserver `host.name`, `service.name` et les champs `data_stream.*` utilisés
  par les dashboards.
- Surveiller l’état `Healthy` de l’agent, les erreurs d’output et le débit des
  data streams `logs-*` et `metrics-*`.

Fleet fournit la supervision OpAMP de l’agent, mais ne pilote pas sa collecte et
ne fournit pas de quota global de débit Elasticsearch. Pour un plafond strict,
appliquer une limite en amont par VM ou par réseau et compléter par le filtrage.

## Contrôles et alertes

Créer des alertes sur les signaux suivants :

- taux de rejet ou d’erreur de l’agent, du Collecteur Edge et du Collector backend ;
- remplissage des queues locales ;
- consumer lag des topics `otel-traces-*`, `otel-logs-*` et `otel-metrics-*` ;
- taux de réponse `429` et erreurs d’indexation Elasticsearch ;
- volume d’événements par `service.name`, `kubernetes.namespace.name` et
  `host.name` ;
- nombre de séries actives et cardinalité des métriques.

Une limitation est opérationnelle seulement si son seuil, son action de
dépassement, sa métrique de saturation et sa procédure de retour à la normale
sont documentés.

## Mise en œuvre dans le dépôt

Les réglages actuels fournissent du batch, une protection mémoire et un buffer
pour les flux EDOT. Ils ne définissent pas de quotas numériques par source.
Avant de fixer ces quotas :

1. mesurer le débit avec `make dashboards-verify` et les métriques des
   Collectors ;
2. choisir un budget séparé pour les traces, les logs et les métriques ;
3. ajouter les limites dans les manifests de l’architecture active ;
4. valider le rendu avec `make kubernetes-validate` ;
5. provoquer un dépassement contrôlé et vérifier le rejet, le lag et la
   reprise.
