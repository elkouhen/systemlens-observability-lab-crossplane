# ADR-001 : choisir le chemin de données EDOT avec Kafka

## Statut

Accepted

## Date

2026-09-25

## Contexte

Les agents EDOT des VM, les collecteurs Kubernetes et les applications doivent
converger vers une chaîne de collecte observable et reproductible. Le dépôt
décrit déjà un Collecteur Edge sur `otel-edge-01`, un Kafka OTel sur
`otel-backend-01`, un exporteur Kafka EDOT sur le backend et Elasticsearch sur
`elk-01`.

L'architecture doit conserver un contrôle distinct par client au point d'entrée
Edge, afin de contrôler séparément les données remontées par chacun d'eux. Elle
doit ensuite découpler l'émission des signaux et leur écriture dans
Elasticsearch. Elle doit également bufferiser les signaux pour absorber les
pointes de charge et les écarts temporaires, dans les limites de capacité et de
rétention du cluster Kafka.

Le tampon Kafka sépare l'émission des signaux et leur écriture dans
Elasticsearch. Les topics sont séparés par signal afin que les logs, métriques
et traces soient décodés par le receiver Kafka avec leur format attendu.

## Décision

L'architecture de référence suit le chemin suivant pour les signaux EDOT :

```text
EDOT standalone → OTLP → otel-edge-01 → Kafka OTel → backend OTel → Elasticsearch
```

Les applications et les collecteurs Kubernetes utilisent également le
Collecteur Edge comme point d'entrée OTLP. Le backend consomme les topics Kafka
séparés par signal et exporte les données vers Elasticsearch. Les traces
peuvent passer par APM Server selon la configuration du backend ; les métriques
et les logs sont exportés vers Elasticsearch.

Cette décision fixe le chemin de données. Elle ne décide pas du mode de gestion
des agents EDOT, qui est traité dans [ADR-002](ADR-002-edot-standalone-ou-managed-by-fleet.md).

## Alternatives considérées

### Export direct vers Elasticsearch

Cette option est écartée parce que l'architecture doit rester découplée entre
la collecte des signaux et leur écriture dans Elasticsearch.

### Export direct vers Elasticsearch depuis le Collecteur Edge

C'est l'Edge qui porte la responsabilité de la collecte côté client. Un export
direct depuis l'Edge vers Elasticsearch supprimerait le découplage entre la
collecte côté client et l'écriture dans Elasticsearch. Il limiterait le
contrôle des données remontées par chaque client et rendrait plus difficile
l'arrêt sélectif de l'acheminement d'un client sans modifier la collecte des
autres. Cette option est écartée pour conserver un contrôle indépendant par
client et un chemin de données découplé.

### Chaîne applications vers Logstash vers Elasticsearch

Cette option ferait envoyer directement les signaux des applications à
Logstash, qui les transformerait puis les exporterait vers Elasticsearch. Elle
ajoute un composant de pipeline, des configurations de filtres et des
responsabilités d'exploitation propres à Logstash.

Cette option est écartée pour trois raisons :

- elle ne fournit pas, dans la chaîne retenue, le chemin OTLP natif et homogène
  attendu pour les logs, métriques et traces ; le support OTLP documenté pour
  Logstash concerne notamment l'export de ses métriques internes, tandis que
  ses plugins d'entrée ne proposent pas de récepteur OTLP générique pour cette
  chaîne ([plugins d'entrée Logstash](https://www.elastic.co/docs/reference/logstash/plugins/input-plugins)) ;
- elle augmente la complexité opérationnelle avec des pipelines, filtres,
  plugins, mappings et mécanismes de reprise à maintenir ;
- elle est moins robuste pour le découplage et les fortes charges que la chaîne
  Collecteur OTel Gateway plus Kafka. Une file persistante Logstash protège
  contre certaines interruptions, mais elle reste locale au nœud et doit être
  dimensionnée et répliquée séparément. Une file distribuée devrait alors être
  ajoutée, ce qui réintroduirait un composant et une complexité supplémentaires
  ([files persistantes Logstash](https://www.elastic.co/docs/reference/logstash/persistent-queues),
  [résilience des files Logstash](https://www.elastic.co/docs/reference/logstash/queues-data-resiliency)).

La chaîne OTLP vers une gateway OTel puis Kafka conserve un modèle de collecte
commun pour les trois signaux, sépare le traitement de l'écriture et fournit
le buffering distribué attendu. Elastic recommande également une gateway
Elastic Agent ou OTel comme couche d'ingestion unifiée pour les signaux OTLP
dans les environnements hôtes et VM ([architecture Elastic OpenTelemetry](https://www.elastic.co/docs/reference/opentelemetry/architecture/hosts_vms)).

### Collecteur OTel vers Kafka vers Kafka Connect vers Elasticsearch

Cette option conserverait le Collecteur OTel et Kafka comme points de collecte
et de découplage, puis remplacerait le backend OTel par Kafka Connect et un
connecteur sink Elasticsearch :

```text
EDOT standalone → OTLP → otel-edge-01 → Kafka OTel → Kafka Connect → Elasticsearch
```

Kafka Connect fournit un runtime distribué pour les connecteurs sink, la
gestion des offsets et la répartition des tâches entre workers ([documentation
Kafka Connect](https://kafka.apache.org/43/kafka-connect/)). Cette solution
serait adaptée si Kafka devait alimenter plusieurs systèmes cibles ou si les
connecteurs Kafka constituaient déjà le standard d'intégration de la
plateforme. Elastic documente également une architecture dans laquelle un
connecteur Kafka ES Sink lit Kafka et écrit dans Elasticsearch ([architecture
Elastic avec Kafka ES Sink](https://www.elastic.co/docs/manage-data/ingest/ingest-reference-architectures/agent-kafka-es)).

Cette option est écartée pour le lab, car elle ne correspond pas à
l'architecture de référence proposée par Elastic. Kafka Connect est moins
adapté qu'un exporteur OTel pour exporter les signaux EDOT vers
Elasticsearch. Cette solution ajouterait Kafka Connect et un connecteur à
exploiter alors que le backend OTel couvre déjà l'export des signaux vers
Elasticsearch. Cette solution déplacerait également le décodage des messages
OTLP, le mapping des champs et le routage par signal
dans la configuration du connecteur et de ses convertisseurs. Le chemin retenu
garde ces responsabilités dans le backend OTel, avec un contrôle explicite des
receivers et des exporters pour les logs, métriques et traces.

## Conséquences

### Conséquences positives

- le chemin des signaux est identique pour les sources Kubernetes et VM après
  leur entrée OTLP ;
- Kafka peut absorber les écarts temporaires entre la production et l'export
  vers Elasticsearch, dans les limites de sa capacité et de sa rétention ;
- les topics séparés rendent le routage et le diagnostic par signal explicites ;
- le point d'entrée OTLP, le buffer et l'exporteur sont déployables et
  vérifiables séparément.

### Coûts et limites

- le chemin ajoute Kafka, un exporteur backend et des contrôles de santé ;
- Kafka fournit le découplage et le buffering attendus dans l'architecture de
  référence Elastic ;
- une panne du backend ou de Kafka peut retarder l'apparition des données dans
  Elasticsearch ;
- les limites de rétention et de capacité Kafka bornent la période pendant
  laquelle les signaux peuvent attendre leur export ;
- la recette doit vérifier chaque signal et chaque étape du chemin, pas seulement
  la présence de traces.

## Références

- [`ansible/README.md`](../ansible/README.md)
- [`ansible/roles/otel_edge/templates/otel-edge.yaml.j2`](../ansible/roles/otel_edge/templates/otel-edge.yaml.j2)
- [`ansible/roles/otel_backend/templates/otel-backend.yaml.j2`](../ansible/roles/otel_backend/templates/otel-backend.yaml.j2)
- [Exporteur Kafka du Collecteur OpenTelemetry](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/kafkaexporter)
- [Récepteur Kafka du Collecteur OpenTelemetry](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/kafkareceiver)
- [Conception de Kafka](https://kafka.apache.org/design/)
- [Documentation Kafka Connect](https://kafka.apache.org/43/kafka-connect/)
- [Architecture Elastic avec Kafka ES Sink](https://www.elastic.co/docs/manage-data/ingest/ingest-reference-architectures/agent-kafka-es)
- [Métriques Logstash via OpenTelemetry](https://www.elastic.co/docs/reference/logstash/monitoring-with-opentelemetry)
- [Plugins d'entrée Logstash](https://www.elastic.co/docs/reference/logstash/plugins/input-plugins)
- [Files persistantes Logstash](https://www.elastic.co/docs/reference/logstash/persistent-queues)
- [Architecture Elastic OpenTelemetry pour les hôtes et les VM](https://www.elastic.co/docs/reference/opentelemetry/architecture/hosts_vms)
