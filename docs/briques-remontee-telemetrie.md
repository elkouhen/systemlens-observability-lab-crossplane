# Briques de remontée de la télémétrie architecture

Ce document décrit la chaîne conservée de remontée des logs, traces et
métriques vers Elastic.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP → Edge → Kafka `otel-traces-supermarche-homologation` | Collector backend (`elasticapm`) → Elasticsearch en OTel natif (ADR-018) |
| Logs applicatifs | Agent Java OpenTelemetry (Logback) | OTLP → Edge → Kafka `otel-logs-supermarche-homologation` | Collector backend → Elasticsearch |
| Métriques applicatives | Micrometer OTLP | OTLP → Edge → Kafka `otel-metrics-supermarche-homologation` | Collector backend → Elasticsearch |
| Métriques runtime de l'agent (JVM, HTTP) | Agent Java OpenTelemetry (scopes `io.opentelemetry.*`) | OTLP → Edge → Kafka `otel-metrics-<plateforme>-homologation` | Collector backend → Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet `kubeletstats`, Deployment `k8s_cluster` | OTLP → Edge → Kafka `otel-metrics-k3s-homologation` | Collector backend → Elasticsearch |
| Logs et métriques VM | Elastic Agent en mode EDOT | OTLP → Edge → Kafka `otel-<signal>-<plateforme>-homologation` | Collector backend → Elasticsearch |

Kafka absorbe les pics entre les producteurs et le Collector backend. Chaque
plateforme a ses trois topics `otel-{logs,metrics,traces}-<plateforme>-<environnement>`
(ADR-015), créés par le rôle Ansible `otel_backend` et consommés par le
groupe `otel-backend`. Chaque client déclare sa plateforme et son
environnement dans sa ressource (`platform.id`,
`deployment.environment.name`) ; le collecteur Edge publie dans le topic de
cette plateforme si elle lui est attribuée dans `otel_platforms`, et rejette
toute autre ressource (ADR-020). Le Collector backend pose
`data_stream.namespace` depuis ces deux attributs, puis applique la
limitation mémoire et la queue disque avant l'export Elasticsearch.

Les flux suivent la convention Elastic : le dataset est celui du receiver, ou `generic` pour les signaux OTLP des applications, le namespace
vaut `<plateforme>_<environnement>` (ADR-019) et la plateforme est aussi le
champ `platform.id`. Les services `supermarket-demo`
écrivent dans `logs-generic.otel-supermarche_homologation` (logs OTel natifs, ADR-012),
`metrics-generic.otel-supermarche_homologation`,
`traces-generic.otel-supermarche_homologation` et les métriques agrégées de l'UI APM
`metrics-<métrique>.1m.otel-supermarche_homologation`, toutes en OTel natif (ADR-018). Les
collecteurs Kubernetes et les agents des VM gardent le dataset de leur
receiver, par exemple `metrics-kubeletstatsreceiver.otel-k3s_homologation` et
`metrics-hostmetricsreceiver.otel-<plateforme>_homologation` : le namespace
sépare `k3s`, `supermarche` et `elk` (ADR-019), comme le champ `platform.id`.

Les cinq VM, `k3s-01` comprise, exécutent Elastic Agent en mode EDOT
standalone. La configuration locale collecte les logs système et les
métriques hôte, puis exporte en OTLP vers l'Edge déclaré par la VM ;
`otel-backend-01` publie directement dans son Kafka local (ADR-005). Les
anciennes policies Fleet de collecte VM ne doivent pas être actives en
parallèle.

## Contrôles

```bash
kubectl -n elastic-stack get deployment,daemonset,pods
make otel-config-validate
make otel-validation
make otel-routing-verify
make otel-gateway-vm-status
architecture/scripts/vm shell supermarket-middleware-01 'sudo /opt/Elastic/Agent/elastic-agent status'
```

## Sources IaC

- Collecteurs Kubernetes : [`otel-kafka.yaml`](../architecture/gitops/otel-pipeline/kubernetes-collectors.yaml) ;
- instrumentation applicative : Application Crossplane [`application.yaml`](../architecture/gitops/supermarket/applications.yaml), rendue par la [Composition](../architecture/gitops/crossplane/apis/application/composition.yaml) ;
- configuration EDOT VM : [`elastic-agent.yml.j2`](../architecture/ansible/roles/elastic_agent/templates/elastic-agent.yml.j2) ;
- Collecteur Edge : [`otel-edge.yaml.j2`](../architecture/ansible/roles/otel_edge/templates/otel-edge.yaml.j2).
