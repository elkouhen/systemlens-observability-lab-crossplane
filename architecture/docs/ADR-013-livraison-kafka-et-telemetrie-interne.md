# ADR-013 : livraison au moins une fois depuis Kafka et télémétrie interne allégée

## Statut

Accepted

Complète [ADR-005](ADR-005-signaux-backend-vers-kafka-local.md) (le Kafka OTel
comme tampon) et [ADR-006](ADR-006-collecteurs-opentelemetry-contrib.md)
(collecteurs contrib).

## Date

2026-11-02

## Contexte

Le collecteur backend lit les topics `otel-*` du Kafka OTel et écrit dans APM
Server et Elasticsearch. Trois défauts étaient constatés :

- **Perte possible à l'arrêt ou en cas de panne aval.** Le receiver Kafka
  commitait l'offset dès la réception. Le processor `batch` acquitte aussi
  avant l'export. Un message reçu mais pas encore écrit était donc perdu si le
  collecteur redémarrait ou si APM Server était indisponible : l'exporteur
  `otlphttp/apm-server` n'avait pas de file persistante.
- **Points rejetés.** Les métriques Java du client Kafka
  (`kafka.consumer.*.avg`/`.max`) valent NaN tant qu'aucune mesure n'existe ;
  l'exporteur Elasticsearch les rejetait avec un avertissement
  « invalid double value ».
- **Télémétrie interne coûteuse.** Les collecteurs exportaient leurs métriques
  internes au niveau `detailed` toutes les 3 s, plus des traces internes, pour
  un usage limité aux dashboards de santé et aux alertes de file.

## Décision

**Backend (`ansible/roles/otel_backend/`)**

- `message_marking.after: true` : l'offset n'est commité qu'après le retour du
  pipeline, c'est-à-dire après l'écriture dans la file persistante de
  l'exporteur. `on_error: false` laisse un message non marqué en cas d'erreur
  transitoire (file pleine, `memory_limiter`) et `error_backoff` le relit.
  `on_permanent_error: true` marque un message illisible ou rejeté
  définitivement, pour ne pas bloquer sa partition.
- Les pipelines Kafka n'ont plus de processor `batch`, qui acquitterait avant
  l'export. Le regroupement est fait par la file de chaque exporteur, après
  persistance.
- `otlphttp/apm-server` a une file persistante (`file_storage`) avec
  regroupement par 512 items et des réessais sans limite de durée ; seule une
  erreur permanente (4xx hors 429) abandonne un lot.
- `elasticsearch/otel` réessaie les erreurs de transport et les 429, pas les
  5xx, pour éviter les doublons d'un bulk partiellement indexé.
- `protocol_version` est retiré du receiver : le client franz-go négocie la
  version de chaque requête avec le broker (`ApiVersions`), alors qu'une
  valeur fixée bornait chaque requête à cette version.
- `filter/invalid-double` supprime les points de gauge et de somme NaN ou
  ±Inf (`x - x != 0`) avant l'exporteur.

**Télémétrie interne (backend, Edge, agents EDOT des VM, collecteurs
Kubernetes)**

- Niveau `normal` au lieu de `detailed`, export toutes les 30 s au lieu de
  3 s ; plus de traces internes.
- L'identité (`service.name`, `service.version`, `service.instance.id`,
  `data_stream.dataset: collectortelemetry`) est portée par
  `service.telemetry.resource` au format `attributes`, ce qui remplace le
  processor `resource/internal-telemetry`.
- Le backend n'expose plus ses métriques internes en Prometheus sur le port
  `8889` : elles sont lues dans Elasticsearch.

## Conséquences

- Livraison au moins une fois entre Kafka et la file des exporteurs : un
  redémarrage peut rejouer des messages déjà écrits (doublons possibles),
  mais n'en perd plus. Quand la file est pleine, Kafka reste le tampon et le
  lag du groupe `otel-backend` augmente.
- Les métriques `otelcol_processor_batch_*` des pipelines Kafka du backend
  disparaissent. `otelcol_exporter_queue_size` (alerte de
  `observability-policies.json`) reste émise au niveau `normal`.
- Les data streams `traces-collectortelemetry*` ne sont plus alimentés.
- Les métriques internes ont une résolution de 30 s.

## Vérification

Les configurations Edge et backend rendues passent
`otelcol-contrib validate` en `0.164.0`. Après déploiement :

```bash
make otel-backend-vm-provision otel-edge-vm-provision elastic-agent-vm-provision kubernetes-observability-deploy
make otel-gateway-vm-status
make dashboards-verify
```

Résultat attendu : les quatre collecteurs démarrent sans erreur, le lag du
groupe `otel-backend` reste proche de 0 et `metrics-collectortelemetry*`
reçoit un point toutes les 30 s par collecteur.

## Note du 2026-11-08 : file persistante de l'Edge

Le collecteur Edge déclarait l'extension `file_storage` sans l'utiliser : son
exporteur `kafka/otlp` gardait les lots en mémoire, perdus sur redémarrage ou
panne prolongée de Kafka. L'exporteur a désormais une `sending_queue`
persistante (`storage: file_storage`, 1 000 lots) et des réessais bornés à
30 min (`retry_on_failure.max_elapsed_time`). La borne évite qu'un refus
durable du broker, par exemple une ACL d'ADR-017 sur le topic d'une seule
plateforme, occupe la file de toutes les plateformes. Le rôle `otel_edge` donne
le répertoire d'état à l'UID 1000 de l'image EDOT. Le processor `batch` reste
avant l'exporteur : il acquitte au client avant la persistance, la perte sur
arrêt brutal se limite à son lot en cours (1 s).

Vérification : `make otel-config-validate`, `make otel-edge-vm-provision`,
puis la présence de fichiers de file dans `/var/lib/observability/otel-edge`
et `make otel-routing-verify`.
