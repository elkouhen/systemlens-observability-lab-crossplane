# Spécification technique

Cette spécification décrit l’implémentation de référence de la chaîne
d’observabilité. Elle précise les composants, les interfaces, les flux et
les contraintes qui réalisent les exigences de la
[spécification fonctionnelle](specification-fonctionnelle.md).

| Élément | Définition |
| --- | --- |
| Nature | Spécification technique de référence |
| Périmètre | Kubernetes, EDOT, Kafka et Elastic de l’architecture active |
| Public | Architectes, développeurs plateforme et opérateurs |
| Version Elastic | `9.4.3` |
| Architecture associée | [Architecture active](architecture.md) |

## 1. Découpage technique

L’architecture sépare les chemins de collecte selon leur origine : les applications et
Kubernetes passent par OpenTelemetry, EDOT et Kafka ; les VM passent par
Elastic Agent EDOT standalone et exportent vers le Collecteur Edge.

Cette séparation réduit le couplage entre la collecte Kubernetes et la
collecte des VM. Elle impose en contrepartie deux modes d’administration : les
collecteurs Kubernetes sont déclarés par Kustomize, tandis que les agents VM
sont provisionnés par Ansible en mode EDOT standalone.

## 2. Topologie des composants

| Composant | Déploiement | Fonction technique |
| --- | --- | --- |
| Collecteur Edge EDOT (`otel-edge`) | `k3s-01`, namespace `elastic-stack` | Authentifier les clients OTLP (`4317`, `4318` : Service et ports du nœud) et publier dans Kafka |
| EDOT DaemonSet | Kubernetes | Collecter les métriques hôte et kubelet prévues par la configuration |
| Argo CD, Crossplane | `tools-01` (hub k3s) | Synchroniser Git et composer les ressources des clusters cibles (ADR-021) |
| Kafka OTel (Strimzi) | `k3s-01` | Tamponner les signaux applicatifs, Kubernetes et VM dans des topics par plateforme |
| Collector backend EDOT | `k3s-01` | Consommer Kafka, traiter les signaux et les exporter vers Elastic |
| Collecteur `otel-middleware` | `k3s-01` | Superviser PostgreSQL, MongoDB et les deux Kafka |
| Elasticsearch (ECK) | `elk-01` | Stocker les signaux et fournir les API d’ingestion et de recherche |
| Kibana | `elk-01` | Fournir Discover, APM, Fleet et les dashboards |
| Fleet Server | `elk-01` | Fournir le plan de contrôle Fleet et le monitoring OpAMP optionnel |
| Elastic Agent EDOT standalone | Chaque VM active | Collecter les logs et métriques des VM et des services intégrés |

Les workloads applicatifs utilisent le namespace `h0tl-supermarche-app`. Les
ressources de plateforme utilisent `elastic-stack`.

## 3. Interfaces et flux

### 3.1 Interfaces Kubernetes

Le Service `otel-edge` expose le Collecteur Edge sur les ports OTLP `4317`
et `4318`. Les applications et les collecteurs Kubernetes utilisent ce Service
comme point d’entrée OTLP.

Le routage externe s’appuie sur Traefik et les hôtes suivants :

- `elasticsearch.observability.test` ;
- `kibana.observability.test` ;
- `fleet.observability.test`.

Ces hôtes sont servis en HTTPS par l'ingress k3s (`192.168.33.50:443`). Le
poste opérateur doit les résoudre vers cette adresse (par exemple dans
`/etc/hosts`). Kibana reste aussi joignable directement sur
`http://192.168.33.40:5601`, adresse utilisée par les cibles du `Makefile`.

Fleet Server se vérifie avec `/api/status`. Sa racine `/` n’est pas une
interface utilisateur.

### 3.2 Interfaces Kafka

Les topics OTLP sont séparés par type de signal, par plateforme et par
environnement, `otel-<signal>-<plateforme>-<environnement>`
([ADR-015](../architecture/docs/ADR-015-topics-par-plateforme-et-configuration-edge.md)) :

| Topic | Producteurs principaux | Consommateur |
| --- | --- | --- |
| `otel-<signal>-supermarche-homologation` | Collecteur Edge : services `supermarket-demo` (namespace `h0tl-supermarche-app`) et supervision de ses bases et de son Kafka | Collector backend |
| `otel-<signal>-k3s-homologation` | Collecteur Edge : collecteurs Kubernetes et VM `k3s-01` | Collector backend |
| `otel-<signal>-demo-homologation` | Collecteur Edge : `demo-api` (namespace `h0tl-demo-app`) | Collector backend |
| `otel-<signal>-elk-homologation` | Collecteur Edge : VM `elk-01`, télémétrie de l'Edge, supervision du Kafka OTel | Collector backend |

Chaque client déclare `platform.id` et `deployment.environment.name` ; le
collecteur Edge publie dans le topic de cette plateforme si `otel_platforms`
la lui attribue et rejette toute autre ressource
([ADR-020](../architecture/docs/ADR-020-plateforme-declaree-par-le-client.md)).
Le backend tire de ces attributs le namespace `<plateforme>_<environnement>`
([ADR-019](../architecture/docs/ADR-019-namespace-par-plateforme.md)) ; le
dataset est celui du receiver, ou `generic` pour les signaux OTLP des
applications :
`logs-generic.otel-supermarche_homologation` (ADR-012),
`metrics-generic.otel-supermarche_homologation`,
`metrics-kubeletstatsreceiver.otel-k3s_homologation`,
`metrics-hostmetricsreceiver.otel-elk_homologation`. Les signaux APM prennent le
namespace `<plateforme>_<environnement>` :
`traces-apm-supermarche_homologation`,
`logs-apm.error-supermarche_homologation` et
`metrics-apm.<métrique>.1m-supermarche_homologation`, ces derniers rangés par
le pipeline Elasticsearch `apm-route-namespace`.
Le groupe de consommation du backend est `otel-backend`. La séparation des
topics évite de décoder des payloads de types différents dans un même flux
et isole chaque plateforme dans Kafka.

### 3.3 Flux VM

Chaque VM active, `k3s-01` comprise, exécute un Elastic Agent EDOT
standalone. Il collecte les logs locaux et les métriques hôte, puis les
publie en OTLP vers l'Edge déclaré par la VM ; les signaux suivent ensuite
les topics de la plateforme de la VM jusqu’au Collector backend. Le hub
`tools-01` n'a pas d'agent EDOT.

## 4. Configuration et sources IaC

| Domaine | Source versionnée |
| --- | --- |
| Architecture et manifests Kubernetes | `architecture/gitops/` (un répertoire par groupe) |
| Collecteurs et buffer Kafka | `architecture/gitops/otel-pipeline/kubernetes-collectors.yaml` |
| Instrumentation applicative | `architecture/gitops/supermarket/applications.yaml` (Application Crossplane, `architecture/gitops/crossplane/apis/application/composition.yaml`) |
| Provisionnement des VM | `architecture/ansible/` |
| Configuration EDOT VM et intégrations Elastic | `architecture/ansible/roles/elastic_agent/` et `architecture/gitops/elastic/assets/fleet/` |
| Dashboards et objets Kibana | `architecture/gitops/elastic/assets/dashboards/` |
| Validation partagée | `validation/otel/` et cibles du `Makefile` |

Toute modification durable doit être réalisée dans ces sources puis appliquée
avec la cible `Makefile` adaptée. Les secrets, mots de passe et jetons restent
hors Git.

## 5. Contraintes techniques

### 5.1 Déploiement déclaratif

Kubernetes est géré par Kustomize. Ansible est réservé au provisionnement des
VM et aux services qui ne relèvent pas du cluster. Les rôles Ansible doivent
rester idempotents.

### 5.2 Administration Fleet

Les collecteurs EDOT Kubernetes et les agents EDOT standalone des VM sont
configurés par les sources IaC correspondantes. Le monitoring Fleet OpAMP est
optionnel et ne fait pas partie du chemin de collecte.

### 5.3 Sécurité des secrets

Les mots de passe et clés d’API sont fournis par les variables d’environnement,
les Secrets Kubernetes ou les scripts de credentials prévus par le dépôt. Ils
ne doivent pas apparaître dans les manifests versionnés, les logs ou la
documentation.

### 5.4 Transport des signaux

Kafka fournit le tampon des flux applicatifs, Kubernetes et VM. Le Collector
backend applique le traitement et l’export vers Elastic. Les VM ne passent pas
par un collecteur Kubernetes intermédiaire.

## 6. Déploiement et validation

Valider les sources sans appliquer de ressource :

```bash
make kubernetes-validate
make ansible-validate
```

Déployer la plateforme et l’application avec les cibles prévues par le
Makefile :

```bash
export POSTGRESQL_PASSWORD='...'
make vms-up
make vm-status
make deploy
```

Vérifier la chaîne après déploiement :

```bash
make otel-validation
make kafka-jolokia-verify
make dashboards-verify
```

Les contrôles d’état complémentaires et les procédures de dépannage sont
déclarés dans le `Makefile` et les README des composants.

## 7. Critères techniques d’acceptation

| ID | Contrôle | Critère de succès |
| --- | --- | --- |
| TA-01 | `make kubernetes-validate` | Le rendu Kustomize est généré sans erreur |
| TA-02 | `make ansible-validate` | Les playbooks de l’architecture passent le contrôle de syntaxe |
| TA-03 | `make otel-validation` | Les flux OTLP attendus sont validés |
| TA-04 | `make kafka-jolokia-verify` | Les métriques Kafka attendues sont accessibles |
| TA-05 | `make dashboards-verify` | Les datasets nécessaires aux dashboards sont récents |
| TA-06 | Fleet et Discover | Les données VM sont présentes et séparées des topics OTLP |

## 8. Références

- [Architecture](architecture.md) : invariants et topologie ;
- [Spécification fonctionnelle](specification-fonctionnelle.md) :
  capacités et critères fonctionnels ;
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  chaîne détaillée et sources IaC ;
- [README de l'architecture](../architecture/README.md) : flux et composants
  de la plateforme.
