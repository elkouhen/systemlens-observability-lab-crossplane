# ADR-008 : instrumenter les applications avec le seul agent Java OpenTelemetry

## Statut

Accepted

Amendé par [ADR-012](ADR-012-logs-otel-natifs-sans-ecs.md) : corrélation
logs/traces.

## Date

2026-11-02

## Contexte

Les traces applicatives de `supermarket-demo` passent déjà par l'agent Java
OpenTelemetry, le collecteur Edge, Kafka `otel-traces` et le collecteur
backend avant APM Server. L'image embarquait pourtant encore l'agent Java
Elastic APM : l'`ENTRYPOINT` l'attachait, le patch Kubernetes le désactivait
avec `ELASTIC_APM_ENABLED=false` et attachait l'agent OTel par
`JAVA_TOOL_OPTIONS`. Une image lancée hors de ce patch démarrait donc avec
l'agent Elastic actif et sans agent OTel.

## Décision

- L'agent Java OpenTelemetry est le seul agent d'instrumentation des trois
  services. L'agent Java Elastic APM est retiré de l'image.
- L'`ENTRYPOINT` de chaque cible du `Dockerfile` attache l'agent avec
  `-javaagent:/opt/opentelemetry-javaagent.jar` et fixe `OTEL_SERVICE_NAME`.
  L'image est ainsi instrumentée par construction, y compris hors Kubernetes.
- L'instrumentation produite par l'Application Crossplane (`architecture/platform/crossplane/applications/composition.yaml`)
  ne fait que configurer l'agent :
  `OTEL_JAVAAGENT_CONFIGURATION_FILE`, attributs de ressource et clé du
  collecteur Edge. Il ne contient plus de `-javaagent`, ce qui évite un double
  attachement.
- La corrélation logs/traces repose sur l'agent OTel, qui exporte les logs
  Logback en OTLP avec leur `trace_id` et leur `span_id` (ADR-012). Le format
  ECS de stdout et la copie en `trace.id` par le collecteur backend sont
  retirés.

## Alternatives considérées

- **Attacher l'agent par `JAVA_TOOL_OPTIONS` dans Kubernetes** : l'image
  resterait sans instrumentation hors du patch, et la règle serait répartie
  entre l'image et le manifest.
- **Conserver l'agent Elastic désactivé** : il garde un second chemin
  d'instrumentation inutilisé et des variables `ELASTIC_APM_*` trompeuses.

## Conséquences

- Les services n'ont plus de variable `ELASTIC_APM_*` ; la cible Makefile
  `apm-token-sync`, qui copiait le token APM pour l'agent Elastic, est
  supprimée.
- APM Server, l'intégration APM Fleet et l'interface APM de Kibana restent
  utilisés : ils reçoivent les traces OTel du collecteur backend.
- Le manifest et l'image doivent être déployés ensemble : une image antérieure
  attache encore l'agent Elastic, sans plus le désactiver ni attacher l'agent
  OTel.

## Vérification

`python3 architecture/platform/crossplane/scripts/applications.py kubernetes/apps/supermarket-demo/application.yaml`
et la Composition ne rendent aucune
variable `ELASTIC_APM_*` ni aucun `-javaagent`. L'agent est attaché une seule
fois, par l'`ENTRYPOINT` des images construites par `make apps-build`. Après
déploiement, `make trace-context-verify` contrôle la propagation et les logs
corrélés.
