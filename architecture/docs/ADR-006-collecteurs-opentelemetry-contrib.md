# ADR-006 : exécuter les collecteurs du lab avec OpenTelemetry Collector Contrib

## Statut

Superseded par [ADR-014](ADR-014-retour-collecteurs-edot.md) : les quatre
collecteurs sont revenus sur EDOT le 2026-11-02. La souscription par regex
décrite ici est conservée.

## Date

2026-11-02

## Contexte

Les quatre collecteurs du chemin de données utilisaient l'image EDOT
`docker.elastic.co/elastic-agent/elastic-otel-collector:9.5.4` :

| Collecteur | Emplacement | Rôle |
| --- | --- | --- |
| `otel-kubernetes` (DaemonSet) | `platform/kubernetes/base/observability/otel-kafka.yaml` | Métriques hôte et kubelet → Edge (logs des pods retirés par ADR-012) |
| `otel-kubernetes-cluster` (Deployment) | même fichier | Métriques du cluster → Edge |
| Collecteur Edge | `ansible/roles/otel_edge/` sur `otel-edge-01` | OTLP authentifié → Kafka OTel |
| Collecteur backend | `ansible/roles/otel_backend/` sur `otel-backend-01` | Kafka OTel → APM Server / Elasticsearch |

Leurs configurations n'utilisent que des composants upstream (core et contrib) :
`otlp`, `kafka`, `filelog`, `hostmetrics`, `kubeletstats`, `k8s_cluster`,
`prometheus`, `k8sattributes`, `transform`, `cumulativetodelta`,
`bearertokenauth`, `file_storage`, `health_check`, `otlp`/`otlphttp` et
`elasticsearch`. Aucun composant propre à Elastic (`elasticapm`, `apmconfig`,
`elasticinframetrics`) n'est utilisé : les traces passent par APM Server, qui
calcule lui-même les métriques APM agrégées.

## Décision

Ces quatre collecteurs utilisent l'image communautaire
`otel/opentelemetry-collector-contrib` (`0.162.0` à l'origine de cette
décision, `0.164.0` depuis le 2026-11-02).

- La version est portée par `otel_collector_contrib_version` dans
  `ansible/inventory/group_vars/all.yml` pour Edge et backend, et figée dans le
  manifest Kustomize pour Kubernetes. Les deux valeurs doivent rester alignées.
- Le backend s'abonne aux topics Kafka OTel par expression régulière
  (`^otel-<signal>(-.+)?$`), avec `initial_offset: earliest` pour ne pas perdre
  les premiers messages d'un topic découvert après le démarrage.

Les Elastic Agent des VM restent en mode EDOT standalone supervisé par Fleet
via OpAMP : ADR-002 reste valable pour eux.

## Conséquences

- Le chemin de données d'ADR-001 est inchangé : seules l'image et l'UID du
  conteneur changent (10001 au lieu de 1000 ; le fichier de clés Edge est
  détenu par cet UID).
- Les collecteurs ne sont plus couverts par le support Elastic, et la
  compatibilité de l'exporteur `elasticsearch` avec la version de la stack
  doit être vérifiée à chaque montée de version de contrib.
- Ajouter un composant propre à Elastic (par exemple `elasticapm` pour envoyer
  les traces directement dans Elasticsearch sans APM Server) imposerait de
  revenir à EDOT ou de construire une distribution avec `ocb`.
- Deux lignes de versions coexistent : Elastic `9.5.4` pour la stack et les
  agents VM, contrib (`otel_collector_contrib_version`) pour les collecteurs.

## Vérification

Les configurations ont été validées avec
`otelcol-contrib validate` de l'image `0.162.0`, et la souscription par regex
a été testée sur un broker Kafka 3.9 : les topics `otel-logs` et
`otel-logs-<suffixe>` sont consommés, `otel-logsX` est ignoré, et un topic
créé après le démarrage est découvert et lu depuis son début.
