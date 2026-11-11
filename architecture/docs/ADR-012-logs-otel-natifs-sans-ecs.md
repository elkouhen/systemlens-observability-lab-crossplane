# ADR-012 : plus d'ECS pour les logs, logs applicatifs exportés par l'agent OTel

## Statut

Accepted

Amende [ADR-008](ADR-008-agent-java-opentelemetry-seul.md) (corrélation
logs/traces) et [ADR-010](ADR-010-dataset-application-namespace-environnement.md)
(nom du data stream des logs). APM Server et son modèle (traces, erreurs et
agrégats APM) ne changent pas.

## Date

2026-11-02

## Contexte

Les logs applicatifs suivaient un chemin propre à ECS : Spring Boot écrivait
un JSON ECS sur stdout (`LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs`), le
DaemonSet `otel-kubernetes` lisait les fichiers des pods et décodait ce JSON,
puis le collecteur backend recopiait `trace_id` en `trace.id` et forçait le
mode de mapping ECS (`transform/ecs-log-correlation`). Les métriques et les
logs PostgreSQL étaient déjà OTel natifs.

Ce chemin mêlait deux modèles : les logs portaient des champs ECS
(`ecs.version`, `log.level`, `message`) alors que tout le reste de la chaîne
est OTel. Le contexte de trace était reconstruit depuis le texte de stdout.
Décision produit : plus d'ECS pour les logs et les métriques.

## Décision

- **Source** : l'agent Java OpenTelemetry exporte les logs Logback en OTLP
  (`otel.logs.exporter=otlp`), par le même endpoint et la même clé Bearer que
  les traces, vers le collecteur Edge. Chaque log émis dans un span porte
  nativement `trace_id` et `span_id`. Les paires clé-valeur SLF4J
  (`addKeyValue`) deviennent des attributs du log
  (`experimental.capture-key-value-pair-attributes`) ; `thread.name` et
  `thread.id` sont ajoutés (`experimental-log-attributes`). La ressource du
  log est celle de l'agent : `service.name`, `service.version`,
  `deployment.environment`, `k8s.namespace.name`, `k8s.pod.name`, nœud.
- **stdout** : le format ECS est retiré. stdout reste le texte par défaut de
  Spring Boot, pour `kubectl logs`.
- **DaemonSet** : `otel-kubernetes` ne lit plus les fichiers des pods ; seul
  son pipeline de métriques reste. Le receiver `filelog`, son décodage JSON
  ECS et le filtre associé sont retirés, ce qui évite tout doublon.
- **Edge** : inchangé. La règle `k8s.namespace.name` =
  `h0tl-supermarche-app` de `transform/kafka-topic` route les logs de
  l'agent vers `otel-logs-supermarche` avec le dataset `supermarche`
  (topic `otel-logs-supermarche-homologation` depuis la note du 2026-11-02
  d'ADR-007).
- **Backend** : `transform/ecs-log-correlation` est supprimé. Tous les flux
  indexés par l'exporteur Elasticsearch sont en mode de mapping OTel (défaut)
  et leur dataset prend le suffixe `.otel`.

| Flux de logs | Avant | Après |
| --- | --- | --- |
| Logs des services `supermarket-demo` | `logs-supermarche-homologation` | `logs-supermarche.otel-homologation` |
| Fichiers de logs des VM (agents EDOT) | `logs-generic-default` | `logs-generic.otel-default` |
| Logs internes des collecteurs Edge et EDOT des VM | `logs-collectortelemetry-default` | `logs-collectortelemetry.otel-default` |
| Logs internes du collecteur backend | `logs-collectortelemetry.otel-default` | inchangé |
| Événements PostgreSQL | `logs-postgresqlreceiver.otel-default` | inchangé |

`logs-collectortelemetry-default` continue d'exister : APM Server y écrit les
événements de span des traces internes des collecteurs. C'est le modèle
d'APM Server, hors du périmètre de cette décision, comme `traces-apm*`,
`logs-apm.error-*` et `metrics-apm.*`.

## Champs

Le template `logs-otel@template` (`logs-*.otel-*`) indexe le log OTel :
`body.text`, `severity_text`, `severity_number`, `trace_id`, `span_id`,
`scope.name` (nom du logger), `attributes.*` et `resource.attributes.*`.
`attributes` et `resource.attributes` sont des objets `passthrough` :
`event.action`, `business.units_sold` ou `service.name` restent interrogeables
sous ce nom en KQL, en DSL et en ES|QL. Le template déclare aussi les alias
`message` → `body.text`, `log.level` → `severity_text`, `trace.id` →
`trace_id` et `span.id` → `span_id` : l'onglet Logs d'une transaction APM et
les requêtes existantes sur `logs-*` fonctionnent sans copie de champ.

## Alternatives considérées

- **Garder stdout et le DaemonSet, en mode OTel** : le JSON ECS de stdout
  resterait la source, et le contexte de trace serait toujours reconstruit
  depuis le texte. Rejeté : le modèle ECS persiste dans l'application.
- **Collecter stdout et exporter par l'agent** : chaque log serait indexé
  deux fois.

## Conséquences

- Les logs applicatifs ne dépendent plus du format de stdout ni du runtime de
  conteneurs. Un log émis hors span n'a pas de `trace_id`.
- Note du 2026-11-08 : les loggers des frameworks (Spring, Tomcat, client
  Kafka, Flyway, Hikari, Micrometer) n'émettent qu'à partir de `WARN`, seuls
  ceux de `io.systemlens` restent en `INFO`
  (`LOGGING_LEVEL_*` de `architecture/gitops/supermarket/applications.yaml`). Tout log `INFO`
  porte donc un `trace_id`, hormis la ligne de démarrage de la classe
  `*Application` ; `make observability-schema-verify` le contrôle. Les logs
  sans `trace_id` restants signalent un problème hors requête.
- Une application non Java, ou sans agent OTel, d'un autre namespace doit
  rétablir un receiver `filelog` dans le DaemonSet
  ([apps/ADDING_APPLICATION.md](../../apps/ADDING_APPLICATION.md)).
- Le filtre des messages Kafka `Consumer exception` et `Value Deserializers
  with error:` du DaemonSet disparaît avec lui ; ces messages n'étaient plus
  émis lors de la décision.
- Les logs JUL (Tomcat) sont aussi exportés par l'agent, avec leur niveau
  d'origine (`SEVERE`).
- Les contrôles `trace-context-verify` et `observability-schema-verify`
  lisent `logs-supermarche.otel-*` et `trace_id` ; le data view APM lit
  `logs-supermarche.otel-*`.
- Les data streams `logs-supermarche-homologation` et
  `logs-generic-default`, obsolètes, sont supprimés après vérification.

## Vérification

Le 2026-11-02, après `make otel-backend-vm-provision`,
`make kubernetes-observability-deploy` et `make apps-deploy`, puis dix
commandes et deux commandes en rupture (`make order-service-command`) :

- les logs des trois services arrivent dans
  `logs-supermarche.otel-homologation` avec `severity_text`, `body.text`,
  `resource.attributes.service.name`, et `trace_id`/`span_id` pour les logs
  émis dans une transaction ;
- `logs-supermarche-homologation` et `logs-generic-default` ne reçoivent plus
  rien ; aucun log applicatif ne porte `ecs.version` ;
- une requête sur `trace.id` (alias de `trace_id`) retrouve les logs d'une
  trace APM ;
- `trace-context-verify`, `observability-schema-verify`, `dashboards-verify`
  et `kubernetes-otel-dashboards-verify` réussissent.
