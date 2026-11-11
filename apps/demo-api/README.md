# demo-api : hello world instrumenté par l'agent Java OTel

API Spring Boot minimale, sans base de données ni Kafka, avec un point
d'entrée par signal. Elle forme à elle seule la plateforme `demo` du lab (namespace
`h0tl-demo-app`, ADR-015). Aucun code d'instrumentation : l'agent Java
OpenTelemetry, attaché par l'`ENTRYPOINT`, produit les trois signaux, qui
suivent le chemin agent → collecteur Edge → Kafka
`otel-<signal>-demo-homologation` → collecteur backend → Elasticsearch, en
OTel natif sans conversion ECS (ADR-018).

| Point d'entrée | Signaux |
| --- | --- |
| `GET /api/hello?name=` | Une transaction APM, un log INFO corrélé (`trace_id`, `span_id`) |
| `GET /api/fail?reason=` | Un log ERROR, une transaction en échec HTTP 500 et une erreur APM : l'exception n'est pas traitée et l'instrumentation servlet de l'agent l'enregistre |

En continu, sans trafic, l'agent exporte toutes les 15 secondes les
métriques runtime JVM de la sémantique OTel, celles de l'onglet *Metrics*
de l'UI APM pour un service Java OTel :

| Métrique | Contenu |
| --- | --- |
| `jvm.memory.used`, `jvm.memory.committed`, `jvm.memory.limit`, `jvm.memory.used_after_last_gc` | Mémoire par `jvm.memory.type` (heap, non_heap) et `jvm.memory.pool.name` |
| `jvm.gc.duration` | Histogramme des pauses GC par `jvm.gc.name` et `jvm.gc.action` |
| `jvm.thread.count` | Threads par `jvm.thread.state` et `jvm.thread.daemon` |
| `jvm.class.count`, `jvm.class.loaded`, `jvm.class.unloaded` | Classes chargées |
| `jvm.cpu.recent_utilization`, `jvm.cpu.time`, `jvm.cpu.count` | CPU du processus JVM |
| `jvm.system.cpu.utilization`, `jvm.buffer.memory.used` | Expérimentales, activées par `otel.instrumentation.runtime-telemetry.emit-experimental-telemetry` |
| `http.server.request.duration` | Histogramme des requêtes HTTP entrantes |

La configuration déclarative de l'agent est dans
`architecture/gitops/demo-api/otel-agent.yaml`, chargée par
`OTEL_CONFIG_FILE`, avec un export des métriques toutes les 15 secondes. Les
trois signaux partent en OTLP HTTP sur le port `4318` du Service
`otel-edge`. Les
sondes Kubernetes sont TCP pour ne pas créer de transactions.

## Data streams alimentés

| Signal | Data stream | Filtre |
| --- | --- | --- |
| Logs et erreurs | `logs-generic.otel-demo_homologation` ; une erreur est un événement `exception` avec `attributes.processor.event: error` | `platform.id: demo`, `service.name: demo-api` |
| Métriques JVM et HTTP de l'agent | `metrics-generic.otel-demo_homologation`, champs `metrics.jvm.*` | `service.name: demo-api` |
| Traces | `traces-generic.otel-demo_homologation` | `platform.id: demo` |
| Métriques APM agrégées | `metrics-{transaction,service_transaction,service_destination,service_summary}.1m.otel-demo_homologation` | `service.name: demo-api` |

## Prérequis

- La plateforme `demo` déclarée dans `otel_platforms`
  (`architecture/ansible/inventory/group_vars/all.yml`) avec `otel-edge-01`
  en `publisher`, puis `make otel-backend-vm-provision` (topics) et
  le ConfigMap `otel-edge-config` du Collecteur Edge (plateformes servies). L'Application
  `architecture/gitops/demo-api/application.yaml` déclare `platform.id=demo` et
  `deployment.environment.name=homologation` (ADR-020) ; sans plateforme
  servie, l'Edge rejette les signaux.
- l'image publiée sur GHCR par le workflow GitHub `build-images.yml` (voir
  [la livraison](../README.md#livraison-dune-nouvelle-version)), le cluster k3s et le Secret
  `otel-edge-client-keys`, copié par Crossplane (synchronisé par Argo CD via `make crossplane-apply`, attendu par
  `make demo-api-deploy`).

## Commandes

Depuis `architecture/` :

```bash
make demo-api-test                # test Maven (Java 21)
make images-wait                  # attend les images publiées sur GHCR aux tags de Git
make demo-api-deploy              # attend l'Application architecture/gitops/demo-api/application.yaml
                                  # (incluse dans make deploy)
make demo-api-build               # optionnel : image locale, sans publication
make demo-api-import              # optionnel : import de l'image locale dans k3s
make demo-api-call                # GET /api/hello?name=lab depuis le cluster
make demo-api-call DEMO_API_PATH='/api/fail?reason=demo'
make demo-api-jvm-metrics-verify  # métriques JVM des 5 dernières minutes
make demo-api-logs-follow
```

Le tag de l'image est celui de `architecture/gitops/demo-api/application.yaml` (lu par le
`Makefile` dans `DEMO_API_IMAGE_TAG` et par le workflow GitHub) ; un tag est immuable, en choisir un
nouveau à chaque version, puis committer et pousser : GitHub publie l'image, Argo CD la déploie.

## Vérification

```bash
make demo-api-jvm-metrics-verify
make otel-routing-verify
```

`demo-api-jvm-metrics-verify` affiche `OK` pour `jvm.memory.used`,
`jvm.memory.limit`, `jvm.gc.duration`, `jvm.thread.count`, `jvm.class.count`
et `jvm.cpu.recent_utilization`. Dans Kibana : l'UI APM liste `demo-api` en
`homologation`, ses transactions `GET /api/hello` et `GET /api/fail`,
l'erreur `DemoFailureException` et l'onglet *Metrics* (tableau JVM, mémoire
heap et non-heap, GC, threads, CPU) ; Discover sur `metrics-generic.otel-demo_*` avec
`service.name: demo-api` montre les champs `metrics.jvm.*`.

## Structure

```text
apps/demo-api/
  pom.xml                       Spring Boot 3.4.5, Java 21, starter web seul
  Dockerfile                    build Maven, agent Java OTel attaché par l'ENTRYPOINT
  src/main/java/io/systemlens/demo/
    DemoApiApplication.java     démarrage
    HelloController.java        GET /api/hello, GET /api/fail
architecture/gitops/demo-api/
  base/                         namespace h0tl-demo-app, Deployment, Service
  default/                      overlay : otel/agent.yaml, patch d'instrumentation
```

Le raccordement suit [`apps/ADDING_APPLICATION.md`](../ADDING_APPLICATION.md).
