# Spécification fonctionnelle

Cette spécification décrit les capacités attendues de la plateforme
d’observabilité active pour les applications Java, Kubernetes et les VM du lab.

| Élément | Définition |
| --- | --- |
| Nature | Spécification fonctionnelle de référence |
| Périmètre | Applications Java, workloads Kubernetes et VM de l’architecture active |
| Public | Product owner, développeurs, opérateurs et responsables de l’observabilité |
| Référence technique | [Spécification technique](specification-technique.md) |
| Architecture | [Architecture active](architecture.md) |

## 1. Objectifs

La plateforme doit rendre observables les applications Java et les composants
de l’environnement qui les supportent. Elle doit permettre de collecter,
transporter, consulter et vérifier les traces, logs et métriques sans mélanger
les responsabilités applicatives, Kubernetes et VM.

Les objectifs fonctionnels sont les suivants :

- suivre les traces et métriques émises par les applications Java ;
- collecter les logs et métriques des workloads Kubernetes ;
- collecter les logs et métriques des VM et des services de données ;
- conserver les signaux pendant leur transport lorsque le backend les traite ;
- consulter les données dans Elastic avec leur contexte de source ;
- vérifier la fraîcheur des données et l’état des dashboards.

## 2. Acteurs et périmètre fonctionnel

| Acteur | Besoin couvert |
| --- | --- |
| Développeur | Diagnostiquer une requête applicative avec les traces, logs et métriques associés |
| Opérateur | Vérifier l’état de Kubernetes, des VM et de la chaîne de collecte |
| Responsable observabilité | Consulter les signaux dans Elastic et contrôler les dashboards |
| Application Java | Émettre des traces et exposer ses métriques applicatives |
| Workload Kubernetes | Produire des logs et être couvert par la collecte de la plateforme |
| VM et services de données | Fournir les logs et métriques collectés par Elastic Agent EDOT standalone |

Le périmètre ne comprend pas la définition métier des services Java, la
conservation d’un historique de production ou la gestion d’un cluster Elastic
externe au lab.

## 3. Exigences fonctionnelles

### 3.1 Collecte des applications

**SF-APP-01.** La plateforme doit recevoir les traces applicatives au format
OTLP via le Collecteur Edge exposé par le Service `otel-edge-vm`.

**SF-APP-02.** La plateforme doit collecter les métriques applicatives
exportées par Micrometer en OTLP vers le Collecteur Edge.

**SF-APP-03.** Les signaux applicatifs doivent conserver leur contexte de
service et d’environnement afin de permettre leur filtrage dans Elastic.

### 3.2 Collecte de Kubernetes

**SF-K8S-01.** Les applications Java doivent exporter leurs logs en OTLP par
l'agent OpenTelemetry, au format OTel natif et corrélés aux traces (ADR-012).
La lecture de stdout par le DaemonSet est réservée à un workload sans agent,
déclaré explicitement.

**SF-K8S-02.** La plateforme doit collecter les métriques Kubernetes prévues
par les collecteurs EDOT.

**SF-K8S-03.** Les signaux Kubernetes doivent être consultables séparément des
signaux VM.

### 3.3 Collecte des VM

**SF-VM-01.** Chaque VM active doit exécuter un Elastic Agent EDOT standalone
identifiable par son nom d’hôte. Le monitoring Fleet OpAMP peut être activé
séparément.

**SF-VM-02.** Elastic Agent EDOT standalone doit collecter les logs et
métriques système des VM.

**SF-VM-03.** Elastic Agent EDOT standalone doit collecter les métriques des
services Kafka, MongoDB et PostgreSQL lorsque l’intégration correspondante est
activée.

**SF-VM-04.** La télémétrie VM doit être envoyée vers le Collecteur Edge, puis
Kafka, le Collector backend et Elasticsearch, sans passer par un collecteur
Kubernetes intermédiaire.

### 3.4 Transport et consultation

**SF-TR-01.** Les signaux applicatifs et Kubernetes doivent pouvoir être
transportés par Kafka avant leur traitement backend.

**SF-TR-02.** Les traces, logs et métriques doivent utiliser des flux Kafka
distincts afin d’éviter le mélange des formats de télémétrie.

**SF-TR-03.** Les données ingérées doivent être consultables dans Kibana avec
des filtres sur le type de signal, la source et le dataset.

**SF-TR-04.** Les dashboards fournis par la plateforme doivent être vérifiables
sur des données récentes.

### 3.5 Exploitation et contrôle

**SF-OPS-01.** L’opérateur doit pouvoir valider les manifests Kubernetes et la
syntaxe Ansible sans déployer de ressource.

**SF-OPS-02.** L’opérateur doit pouvoir exécuter une validation OTLP de la
chaîne de collecte.

**SF-OPS-03.** Les secrets et jetons nécessaires au déploiement ne doivent pas
être stockés dans Git.

## 4. Scénarios d’acceptation

| ID | Scénario | Résultat attendu |
| --- | --- | --- |
| AC-01 | L’opérateur exécute `make kubernetes-validate` | Le rendu Kustomize est valide sans application de ressource |
| AC-02 | L’opérateur exécute `make ansible-validate` | Les playbooks Ansible sont syntaxiquement valides sans provisioning |
| AC-03 | Une application émet une trace et expose ses métriques | Les signaux sont transportés par la chaîne OTLP puis visibles dans Elastic |
| AC-04 | Un service applicatif émet un log dans une transaction | Le log est consultable dans `logs-generic.otel-supermarche_*` avec son `trace_id` et son contexte Kubernetes |
| AC-05 | L’agent EDOT standalone de `supermarket-middleware-01` est actif | Les logs et métriques de la VM sont visibles après leur passage par Edge et Kafka |
| AC-06 | L’opérateur exécute `make otel-validation` | La validation OTLP retourne un résultat exploitable |
| AC-07 | L’opérateur exécute `make dashboards-verify` | Les jeux de données attendus par les dashboards sont récents |

## 5. Hors périmètre

Cette spécification ne définit pas :

- les classes Java, les contrats REST ou les messages métier de
  `supermarket-demo` ;
- les paramètres détaillés des receivers, processors et exporters EDOT ;
- les règles de dimensionnement d’un environnement de production ;
- les procédures de restauration des données Elastic ;
- les évolutions d’architectures historiques supprimées du dépôt.

Ces sujets relèvent des documents applicatifs, de la
[spécification technique](specification-technique.md) ou des README locaux.

## 6. Références

- [Architecture](architecture.md) : topologie et invariants ;
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  sources, transport et destinations ;
