# Ajouter une application Java observée

Ce guide décrit le raccordement à la chaîne d'observabilité architecture. Un service est
déclaré comme une `Application` Crossplane (`kubernetes/apps/<application>/application.yaml`) ;
la Composition `architecture/platform/crossplane/applications/composition.yaml` en produit le
Deployment, le Service et l'instrumentation OTel.

Ce guide décrit l'ajout d'une application Java Spring Boot à la chaîne
d'observabilité du lab. Le chemin des signaux est le suivant :

```text
application Java → agent Java OTel → Collecteur Edge → Kafka → Collector backend → Elasticsearch (OTel natif)
```

L'agent Java OTel produit les traces et les logs, Micrometer les métriques
applicatives. Les logs sont OTel natifs, sans format ECS (ADR-012).
Le Collecteur Edge reçoit l'OTLP et publie dans le topic Kafka de la
plateforme que l'application déclare (ADR-020) ; le Collector backend en
fait le namespace du data stream (ADR-019).

L'application `apps/demo-api` est l'exemple minimal de ce guide : un seul
service, sa plateforme `demo`, son Application `kubernetes/apps/demo-api/application.yaml`.
Sans Micrometer, elle laisse l'agent exporter aussi les métriques JVM
(`otel.metrics.exporter=otlp`), au format sémantique OTel. Toutes les
métriques, celles de l'agent comme celles de Micrometer, sont indexées en
mapping OTel natif dans `metrics-<dataset>.otel-<plateforme>_<environnement>` (ADR-018, ADR-019).

## Préparer l'application

L'image doit contenir l'agent Java OpenTelemetry et démarrer la JVM avec
`-javaagent:/opt/opentelemetry-javaagent.jar` dans son `ENTRYPOINT`. C'est le
seul agent d'instrumentation : ne pas ajouter l'agent Java Elastic APM. Le
`Dockerfile` de `supermarket-demo` est la référence du dépôt ; chaque cible
d'image y fixe aussi `OTEL_SERVICE_NAME` pour une exécution hors Kubernetes.

Les logs passent par l'agent : son instrumentation Logback exporte chaque
log en OTLP, avec le `trace_id` et le `span_id` du span courant. Ne pas
configurer de format structuré (`logging.structured.format.console`) ni
d'appender d'export : stdout garde le texte par défaut de Spring Boot, lu par
`kubectl logs` mais pas collecté.

## Déclarer les variables Kubernetes

L'Application ne donne que quelques paramètres : image et tag, port, chemin des sondes,
plateforme OTel (`spec.otel.platform`), export Micrometer et variables propres au service
(`spec.env`). La Composition configure l'agent sans l'attacher une seconde fois : elle monte
la configuration déclarative `otel/agent.yaml`, incorporée par
`architecture/platform/crossplane/scripts/applications.py` puis publiée en ConfigMap
`<application>-otel-agent-config` (son empreinte redémarre les pods), et ajoute :

```yaml
env:
  - name: OTEL_CONFIG_FILE
    value: /opt/opentelemetry/agent.yaml
  - name: OTEL_EDGE_KEY
    valueFrom:
      secretKeyRef:
        name: otel-edge-client-keys
        key: otel-kubernetes-cluster
  - name: OTEL_EXPORTER_OTLP_HEADERS
    value: Authorization=Bearer $(OTEL_EDGE_KEY)
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: service.name=my-service,platform.id=supermarche,deployment.environment.name=homologation,k8s.cluster.name=k3s-01,k8s.namespace.name=h0tl-supermarche-app
```

La Composition complète `OTEL_RESOURCE_ATTRIBUTES` avec le pod et le nœud,
fournis par la Downward API. Ces attributs forment la ressource des traces,
des métriques et des logs : `platform.id` et `deployment.environment.name`
choisissent le topic Kafka, donc le data stream (ADR-020). Le collecteur
Edge publie dans le topic de cette plateforme si elle lui est attribuée dans
`otel_platforms` (`architecture/ansible/inventory/group_vars/all.yml`), et
rejette sinon la ressource : une nouvelle plateforme demande donc une entrée
au registre. Le backend fait de ces deux attributs le namespace du data
stream.

Le fichier `agent.yaml` suit le schéma de configuration déclarative
d'OpenTelemetry (`file_format: "1.0"`). L'agent y lit tout : ressource,
propagateurs, exporteurs OTLP HTTP des trois signaux et options
d'instrumentation. Il ignore alors les variables `OTEL_*` habituelles ; le
fichier reprend `OTEL_RESOURCE_ATTRIBUTES` et `OTEL_EXPORTER_OTLP_HEADERS`
par substitution :

```yaml
resource:
  attributes_list: ${OTEL_RESOURCE_ATTRIBUTES}
logger_provider:
  processors:
    - batch:
        exporter:
          otlp_http:
            endpoint: http://otel-edge-vm.elastic-stack.svc.cluster.local:4318/v1/logs
            headers_list: ${OTEL_EXPORTER_OTLP_HEADERS}
instrumentation/development:
  java:
    logback_appender:
      capture_key_value_pair_attributes/development: true
      experimental_log_attributes/development: true
```

`capture_key_value_pair_attributes` transforme les paires SLF4J
`addKeyValue` en attributs du log (`event.action`, `business.units_sold`) ;
`experimental_log_attributes` ajoute `thread.name` et `thread.id`. Une
configuration invalide n'arrête pas l'application : l'agent journalise
`OpenTelemetry Javaagent failed to start` et l'application tourne sans
télémétrie. Après un déploiement, vérifier l'absence de cette ligne dans les
logs du pod. La clé du collecteur Edge reste dans le secret
`otel-edge-client-keys`, copié par Crossplane (`architecture/platform/crossplane/kubernetes/secrets.yaml`) ; ne
jamais l'inscrire dans un manifest ou dans Git.

Ne pas ajouter `-javaagent` dans `JAVA_TOOL_OPTIONS` : l'agent serait attaché
deux fois, par l'`ENTRYPOINT` et par cette variable.

Une exception traitée par un `@ExceptionHandler` n'atteint pas
l'instrumentation servlet de l'agent et ne produit pas d'erreur APM, même si
la réponse est un 500. Pour qu'elle apparaisse dans l'UI APM, l'enregistrer
sur le span courant avec l'API OpenTelemetry, reliée à l'agent
(`io.opentelemetry:opentelemetry-api`, version gérée par le BOM de Spring
Boot) : `Span.current().recordException(e)` puis
`setStatus(StatusCode.ERROR, ...)`.

## Convention d'environnement

Le namespace Kubernetes suit le format
`<type><ptf_sur_3_caracteres>-<namespace>`, par exemple
`h0tl-supermarche-app` : `h` pour homologation, `0tl` pour la plateforme,
`supermarche-app` pour le périmètre applicatif.

Aucun traitement ne découpe cette valeur. L'environnement affiché par l'UI APM
vient de l'attribut de ressource `deployment.environment.name` posé par la Composition
(nom courant d'OpenTelemetry, à la place de `deployment.environment`), indexé
en `service.environment` sur les traces et les métriques APM. Avec
`platform.id`, il choisit le topic Kafka et le data stream (ADR-020). Le
namespace est transmis par `k8s.namespace.name` et indexé en
`kubernetes.namespace`.

## Data streams alimentés

Le dataset est `generic`, celui que l'exporteur donne aux signaux OTLP d'une
application ; le namespace nomme la plateforme et l'environnement (ADR-019),
ce qui évite de répéter la plateforme dans le nom. La plateforme est aussi le
champ `platform.id`. Le collecteur Edge publie les
signaux dont la ressource porte `platform.id` = `supermarche` et
`deployment.environment.name` = `homologation` dans les topics
`otel-<signal>-supermarche-homologation` de la plateforme `supermarche`
(ADR-015, ADR-020). Le collecteur backend en fait le namespace
`supermarche_homologation`. Tous les signaux sont OTel natifs (ADR-018) :

| Signal | Data stream |
| --- | --- |
| Traces | `traces-generic.otel-supermarche_homologation` |
| Métriques APM agrégées | `metrics-{transaction,service_transaction,service_destination,service_summary}.1m.otel-supermarche_homologation` |
| Métriques Micrometer et JVM | `metrics-generic.otel-supermarche_homologation` |
| Logs applicatifs | `logs-generic.otel-supermarche_homologation` |

Les trois signaux reçoivent le suffixe `.otel` du mode de mapping OTel. Le
processeur `elasticapm` du collecteur backend enrichit les traces pour l'UI
APM, et le connecteur `elasticapm` en tire les métriques agrégées ; les
intervalles `10m` et `60m` suivent la même règle. Les métriques Kubernetes des pods (`kubeletstats`, `k8s_cluster`) gardent le
dataset de leur receiver, en namespace `k3s_homologation`.

### Déclarer une nouvelle application comme plateforme

Un namespace Kubernetes est une plateforme dans un environnement (ADR-015).
Une nouvelle application demande une plateforme au registre et sa
déclaration dans l'Application (ADR-020).

1. Ajouter le couple à `otel_platforms` dans
   `architecture/ansible/inventory/group_vars/all.yml`, avec l'Edge en
   `publisher` :

   ```yaml
   - platform: caisse
     environment: homologation
     publishers: [otel-edge-01]
   ```

2. Déclarer la plateforme dans l'Application : `spec.otel.platform: caisse`
   (`deployment.environment.name` vaut `homologation` par défaut).
   Ses signaux iront dans `logs-generic.otel-caisse_homologation`,
   `metrics-generic.otel-caisse_homologation` et
   `traces-generic.otel-caisse_homologation`,
   tous avec `platform.id` = `caisse`.
3. Valider avec `make otel-config-validate`, créer les topics avec
   `make otel-backend-vm-provision`, puis appliquer la liste des plateformes
   servies avec `make otel-edge-vm-provision`.

L'attribut `data_stream.dataset` posé par l'application est supprimé par
l'Edge (ADR-019). Sans plateforme au registre, les signaux de l'application
sont rejetés par l'Edge et comptés par `make otel-routing-verify`.

Les trois signaux portent la ressource de l'agent sous `resource.attributes`
(`service.name`,
`service.version`, `deployment.environment.name`, `k8s.*`, `telemetry.distro.*`).

### Noms des spans HTTP client

Sans gabarit, la convention nomme un span HTTP client par sa seule méthode
(`POST`). Les règles génériques de `agent.yaml`
([ADR-011](../architecture/docs/ADR-011-nom-des-spans-http-client.md))
donnent à tout appel le nom `{méthode} {chemin}`, sans liste d'URL. Un
segment identifiant devient `{id}` : `GET /api/products/PASTA-500G` devient
`GET /api/products/{id}`.

`pattern` est une expression régulière ancrée sur l'URL complète, `template`
un remplacement (`$1`, `$2`) qui devient l'attribut `url.template`. La
première règle qui correspond l'emporte. Pour un identifiant d'une autre
forme, par exemple un code en minuscules, ajouter une règle plus précise
avant les règles génériques. Le client HTTP du JDK, sous `RestTemplate`,
reprend le gabarit dans le nom ; `HttpURLConnection` ne pose que
l'attribut.

## Application sans agent OTel

Le DaemonSet `otel-kubernetes` ne collecte plus les fichiers des pods : une
application Java exporte ses logs par l'agent, ce qui évite les doublons.
Pour une application d'un autre namespace qui ne peut écrire que sur stdout,
rétablir dans `architecture/platform/kubernetes/base/observability/otel-kafka.yaml` :

- le montage `hostPath` `/var/log/pods` (lecture seule) du DaemonSet ;
- un receiver `filelog` limité à ce namespace, avec l'opérateur `container` :

  ```yaml
  filelog/kubernetes:
    include: [/var/log/pods/<namespace>_*/*/*.log]
    start_at: end
    include_file_path: true
    operators:
      - type: container
  ```

- un pipeline `logs` : `filelog/kubernetes` → `memory_limiter`, un
  processor `resource` posant `platform.id` et
  `deployment.environment.name` de cette application, `batch` →
  `otlp/edge`.

L'opérateur `container` tire `k8s.namespace.name` et `k8s.pod.name` du chemin
du fichier ; l'Edge publie ces logs dans le topic de la plateforme déclarée
(ADR-020). Ne jamais inclure `h0tl-supermarche-app` ni `elastic-stack`. Appliquer ensuite
`make kubernetes-validate`, puis `make kubernetes-observability-deploy`.

## Vérifier le résultat

Après le déploiement de l'application, générer une requête métier puis utiliser
Discover avec les filtres suivants :

```kql
# Traces, erreurs et métriques APM en homologation
data_stream.namespace:"supermarche_homologation"
and service.name:"my-service"
and service.environment:"homologation"
and agent.name:"opentelemetry/java/opentelemetry-java-instrumentation"
```

```kql
# Logs applicatifs (data view sur logs-generic.otel-supermarche_*)
data_stream.dataset:"generic.otel"
and data_stream.namespace:"supermarche_homologation"
and service.name:"my-service"
and k8s.namespace.name:"h0tl-supermarche-app"
```

Le contrôle attendu est la présence de la même identité de service dans les
logs, métriques et traces, avec un `trace_id` sur les logs émis dans une
transaction. Le message est dans `body.text` et le niveau dans
`severity_text` ; le template OTel déclare les alias `message`, `log.level`
et `trace.id`, lus par la vue Logs des transactions APM.
`make trace-context-verify` contrôle cette corrélation et
`make observability-schema-verify` la forme des logs.
