# Architecture : Hybride Fleet

L’architecture active du lab utilise Elastic
Stack `9.5.4`, OpenTelemetry et EDOT pour les applications, Kubernetes et les
VM. Les agents des VM sont installés en mode EDOT standalone. Leur supervision
Fleet OpAMP est optionnelle et limitée au monitoring ; leur configuration reste
gérée par les fichiers Ansible versionnés.

## Périmètre

Cette spécification décrit la topologie, les flux de télémétrie, les
responsabilités des composants et les contrôles de l’architecture. Les
commandes détaillées et les prérequis sont dans le README Ansible et le
`Makefile`.

Le code Java et les images applicatives restent partagés entre les composants
du dépôt. Les manifests Kubernetes et le provisionnement des VM sont propres
à l'architecture.

## Topologie

```text
tools-01 (hub k3s) : Argo CD, Crossplane, cert-manager
   │ déploie et configure depuis Git (ADR-021)
   ├──▶ k3s-01 (k3s) : applications Java, PostgreSQL, MongoDB, Kafka métier,
   │                   Kafka OTel, collecteurs OTel (Kubernetes, backend, supervision)
   └──▶ elk-01 (k3s + ECK) : Elasticsearch, Kibana, Fleet Server

Applications, collecteurs Kubernetes, agents EDOT des VM
                 │ OTLP (clé Bearer)
                 ▼
       Collecteur Edge sur otel-edge-01 (VM)
                 │ Kafka SCRAM, NodePort 192.168.33.50:31092
                 ▼
       Kafka OTel dans k3s-01
                 ▼
       Collecteur backend EDOT dans k3s-01
                 ▼
       Elasticsearch sur elk-01 (192.168.33.40:9200) ──▶ Kibana
```

`otel-edge-01` fournit le point d’entrée exposé pour OTLP. `tools-01` est le cluster de gestion :
Argo CD y synchronise `architecture/gitops/` et Crossplane y compose les objets des clusters cibles.
`k3s-01` héberge les applications, leurs bases (CloudNativePG, MongoDB Controllers for Kubernetes),
le Kafka métier et le Kafka OTel (Strimzi), le collecteur backend et l’export vers Elastic.
`elk-01` héberge Elasticsearch, Kibana et Fleet Server sous ECK.

Les namespaces Kubernetes conservés sont `elastic-stack` pour la plateforme
et `h0tl-supermarche-app` pour l’application.

## Flux de télémétrie

Les applications Java et les composants Kubernetes utilisent Kafka comme
tampon entre la collecte et le traitement backend. Les VM envoient leurs logs
et métriques en OTLP au Collecteur Edge avec Elastic Agent EDOT standalone.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP, Edge, Kafka `otel-traces-supermarche-homologation` | EDOT backend (`elasticapm`), Elasticsearch en OTel natif (ADR-018) |
| Logs applicatifs | Agent Java OpenTelemetry (Logback) | OTLP, Edge, Kafka `otel-logs-supermarche-homologation` | EDOT backend, Elasticsearch |
| Métriques applicatives | Micrometer OTLP | OTLP, Edge, Kafka `otel-metrics-supermarche-homologation` | EDOT backend, Elasticsearch |
| Métriques runtime de l'agent (JVM, HTTP) | Agent Java OpenTelemetry | OTLP, Edge, Kafka de la plateforme | EDOT backend, Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet et Deployment | OTLP, Edge, Kafka `otel-metrics-k3s-homologation` | EDOT backend, Elasticsearch |
| Logs et métriques des VM | Elastic Agent EDOT standalone | OTLP, Edge, Kafka de la plateforme de la VM | EDOT backend, Elasticsearch |

Les topics sont séparés par signal, par plateforme et par environnement :
`otel-<signal>-<plateforme>-<environnement>` (ADR-015). Le lab compte quatre
plateformes en `homologation` : `k3s` (cluster et collecteurs Kubernetes, VM
`k3s-01`), `supermarche` (namespace `h0tl-supermarche-app`, supervision de ses
bases et de son Kafka), `demo` (namespace `h0tl-demo-app`, API de
démonstration `demo-api`) et `elk` (VM d'observabilité, collecteurs Edge et
backend). Chaque client déclare sa plateforme et son environnement dans sa
ressource (`platform.id`, `deployment.environment.name`) ; l'Edge publie dans
le topic de cette plateforme si le registre `otel_platforms` la lui attribue,
et rejette sinon la ressource (ADR-020). Le backend pose depuis ces deux
attributs le namespace `<plateforme>_<environnement>` (ADR-019) ; le dataset
est celui du receiver, ou `generic` pour les signaux OTLP des applications :
`logs-generic.otel-supermarche_homologation`,
`metrics-kubeletstatsreceiver.otel-k3s_homologation`,
`traces-generic.otel-supermarche_homologation`. Le Collector backend applique le
traitement nécessaire avant l’export vers Elastic, sans conversion ECS : le
processeur `elasticapm` enrichit les traces et le connecteur `elasticapm` en
tire les métriques agrégées de l'UI APM (ADR-018).

## Responsabilités des composants

| Composant | Responsabilité | Source de configuration |
| --- | --- | --- |
| `otel-edge-01` | Recevoir l’OTLP Kubernetes et VM puis publier dans Kafka | `architecture/ansible/roles/otel_edge/` |
| EDOT DaemonSet | Collecter les métriques `kubeletstats` du nœud | `architecture/gitops/otel-pipeline/k3s-01/` |
| `tools-01` | Synchroniser Git (Argo CD) et composer les clusters cibles (Crossplane) | `architecture/gitops/` |
| Back-ends de `k3s-01` | Fournir Kafka métier, MongoDB et PostgreSQL | `architecture/gitops/supermarket/databases.yaml` |
| Kafka OTel et collecteur backend (`k3s-01`) | Tamponner puis exporter les signaux vers Elastic | `architecture/gitops/otel-pipeline/` |
| Collecteur `otel-middleware` (`k3s-01`) | Superviser PostgreSQL, MongoDB et les deux Kafka | `architecture/gitops/otel-pipeline/k3s-01/` |
| `otel-edge-01` | Exposer les points d’entrée et héberger le Collecteur Edge | `architecture/ansible/` et `architecture/gitops/otel-pipeline/` |
| `elk-01` | Fournir Elasticsearch, Kibana et Fleet Server (ECK) | `architecture/gitops/elastic/` |
| Elastic Agent EDOT | Collecter les logs et métriques de `k3s-01`, `elk-01` et `otel-edge-01` et les exporter vers l'Edge déclaré par la VM | `architecture/ansible/roles/elastic_agent/` |

Les collecteurs Kubernetes et les applications envoient leurs signaux au
Collecteur Edge via le Service `otel-edge-vm`. Les agents EDOT standalone des
VM utilisent directement l’adresse OTLP de ce même collecteur. Tous les flux
suivent ensuite Kafka et le backend.

## Invariants d’architecture

Les contrôles et évolutions de l'architecture doivent conserver les invariants suivants :

1. Les applications et les collecteurs Kubernetes utilisent le namespace
   `elastic-stack` pour les composants de la plateforme.
2. Les signaux OTLP applicatifs et Kubernetes passent par Kafka avant le
   traitement backend.
3. Les topics Kafka distinguent les traces, les logs et les métriques, et
   chaque plateforme dans son environnement ; le backend ne porte aucune
   table de routage.
4. Les VM utilisent Elastic Agent EDOT, déclarent leur plateforme, leur
   environnement et leur Edge, et exportent en OTLP vers ce Collecteur Edge
   avant Kafka et le traitement backend.
5. Les secrets et jetons restent hors Git et sont fournis par les mécanismes
   prévus par le dépôt.
6. Les changements durables de Kubernetes, Fleet, Elastic et Ansible restent
   déclarés dans les fichiers versionnés correspondants.
7. Les clusters cibles ne reçoivent que ce que le hub y déploie depuis Git
   (Argo CD ou Crossplane) ; Ansible se limite aux hôtes (ADR-021).

## Déploiement et vérification

Depuis la racine du dépôt, vérifier l’architecture active puis valider les
manifests sans appliquer de ressource :

```bash
make architecture-status
make kubernetes-validate
make ansible-validate
make otel-config-validate
```

Pour déployer l’architecture complète, fournir les secrets hors Git puis
exécuter :

```bash
export POSTGRESQL_PASSWORD='...'
export MONGODB_PASSWORD='...'
export ELASTIC_PASSWORD='...'
export KIBANA_PASSWORD='...'
make vms-up
make vm-status
make deploy
```

Les variables de mot de passe doivent être fournies hors Git. Les commandes de
déploiement échouent si un secret requis est absent. Derrière un proxy TLS
d'entreprise, le certificat local `certs/zscaler-root-ca.crt` est installé
automatiquement sur les VM et dans les images.

Sur des VM neuves, `make vms-up` ne déploie pas encore le collecteur backend :
sa clé API Elasticsearch n'existe qu'après Elasticsearch. `make deploy`
déploie ensuite Elastic, Fleet, les collecteurs Kubernetes, `supermarket-demo`
et `demo-api`, puis termine le collecteur backend et le monitoring OpAMP.

Les contrôles fonctionnels de la chaîne sont :

```bash
make otel-validation
make otel-kafka-acl-verify
make otel-routing-verify
make trace-context-verify
make observability-schema-verify
make dashboards-verify
```

Le [README de l'architecture](../architecture/README.md) renvoie vers le README
du provisionnement Ansible. Le [document sur les briques de
télémétrie](briques-remontee-telemetrie.md) fournit le détail des sources
IaC de chaque flux.
