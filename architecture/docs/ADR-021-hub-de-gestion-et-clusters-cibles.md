# ADR-021 : un hub de gestion pilote les clusters cibles

## Statut

Accepted, 2026-11-11 (lot 8 du backlog). Remplace la topologie à cinq VM : les VM
`supermarket-middleware-01`, `otel-backend-01` et `otel-edge-01` sont supprimées. Rend caduques
[ADR-004](ADR-004-metrics-backend-vers-kafka-local.md) et
[ADR-005](ADR-005-signaux-backend-vers-kafka-local.md) (agent EDOT du backend publiant dans le
Kafka OTel local) : il n'y a plus de VM backend. Conserve le chemin des signaux (Edge, Kafka OTel,
backend, Elasticsearch), les topics par plateforme (ADR-015), les ACL Kafka (ADR-017) et les data
streams (ADR-019).

## Date

2026-11-11

## Contexte

Après les lots 1 à 7, Crossplane et Argo CD tournaient dans `k3s-01`, à côté des applications,
et configuraient des services installés par Ansible et Podman sur trois VM (`supermarket-middleware-01`,
`otel-backend-01`, `elk-01`). Les back-ends restaient donc hors de Kubernetes : leur cycle de vie
(installation, comptes d'amorçage, mise à jour) passait par des rôles Ansible, et Crossplane ne
pouvait que les configurer. L'objectif du lot 8 est de « faire un maximum avec Crossplane ».

## Décision

- Un cluster k3s de gestion, `tools-01` (192.168.33.60), porte Argo CD, Crossplane et ses
  providers, cert-manager et la clé age. Deux clusters cibles : `k3s-01` (applicatif) et `elk-01`
  (observabilité). Le Collecteur Edge, d'abord resté sur la VM Ansible `otel-edge-01` derrière
  HAProxy, est un Deployment `otel-edge` de `k3s-01` (item H8) : Service `otel-edge` pour les clients
  du cluster, ports du nœud 4317 et 4318 de `192.168.33.50` pour les agents EDOT des VM et le poste
  (redirection Lima). Son identité de producteur reste `otel-edge-01` (publishers de
  `platforms.yaml`, compte Kafka `otel_publisher_otel_edge_01`, ACL inchangées).
- Argo CD enregistre les clusters cibles par des Secrets de cluster créés à l'amorçage
  (`make clusters-register`) ; Crossplane les atteint par provider-kubernetes, une
  `ClusterProviderConfig` par cluster, avec le même kubeconfig. Ces identifiants, régénérés par k3s
  à chaque installation, ne sont pas versionnés.
- Les opérateurs sont des charts Helm synchronisés par Argo CD dans leur cluster cible :
  CloudNativePG, Strimzi et MongoDB Controllers for Kubernetes dans `k3s-01`, ECK dans `elk-01`.
  Les collecteurs OTel de `k3s-01` sont aussi des manifests synchronisés directement.
- Le hub expose des API Crossplane composant les instances dans les clusters cibles :
  `PostgreSQLInstance`, `MongoDBInstance`, `KafkaCluster`, `ObservabilityStack`, en plus
  d'`Application` (désormais composée dans `k3s-01`) et d'`OtelPlatform`. Chaque groupe déclare ses
  instances ; les comptes d'amorçage (`postgres`, `crossplane_admin`, `otel-admin`, `elastic`) sont
  déclarés par ces instances au lieu d'être créés par Ansible.
- La configuration des back-ends reste celle des lots précédents (provider-sql, Terraform
  `Kaginari/mongodb` et `elastic/elasticstack`, provider-kafka, provider-http) ; seuls ses points
  d'accès changent : NodePort de `k3s-01` (192.168.33.50 : 30432, 30017, 31092, 31192) et Services
  LoadBalancer de `elk-01`, qui gardent 192.168.33.40:9200, 5601 et 8220.
- La supervision de PostgreSQL, MongoDB et des deux Kafka passe des agents EDOT des VM supprimées
  au collecteur `otel-middleware` de `k3s-01`, avec les mêmes receivers et les mêmes plateformes,
  donc les mêmes data streams.
- Les Secrets restent chiffrés par SOPS et rendus dans le hub ; les pods des clusters cibles en
  reçoivent une copie par un `Object` (`references.patchesFrom`, résolu dans le hub).

## Conséquences

- Tout ce qui tourne dans un cluster est déclaré dans Git ; Ansible se limite aux hôtes.
- L'Edge publie dans le Kafka OTel par son listener interne ; le NodePort 31092 ne sert plus que
  provider-kafka du hub. Le compte `otel_publisher_otel_backend_01` disparaît.
- La liste des plateformes servies par l'Edge est écrite dans son ConfigMap ; `make
  otel-config-validate` la compare à `platforms.yaml` (`scripts/edge-platforms-check.rb`).
- L'opérateur d'utilisateurs de Strimzi ne gère aucune ACL : le Kafka OTel déclare l'autoriseur
  standard de Kafka en `custom` (`supportsAdminApi: false`). En `simple`, il supprimait toutes les
  ACL de provider-kafka toutes les 2 minutes, malgré `STRIMZI_IGNORED_USERS_PATTERN`.
- L'opérateur d'utilisateurs de Strimzi supprime les comptes SCRAM qu'il ne gère pas : il ignore
  `^otel_` (variable `STRIMZI_IGNORED_USERS_PATTERN`), laissant ces comptes à provider-kafka.
  L'administrateur s'appelle `otel-admin` (nom Kubernetes du `KafkaUser`).
- Un cluster k3s supplémentaire coûte de la mémoire (serveur k3s du hub, nombreux CRD) ; les mesures
  du lot 8 sont dans le backlog.
- Le hub n'a pas d'agent EDOT : il n'est pas supervisé par la chaîne du lab.

## Vérification

`make vms-destroy && make vms-up && make deploy`, puis `make argocd-status` (toutes les
Application Synced et Healthy), `make otel-validate`, `make otel-routing-verify`,
`make otel-kafka-acl-verify`, `make trace-context-verify`, `make application-data-verify`,
`make demo-api-jvm-metrics-verify`, `make dashboards-verify` et
`make postgresql-otel-dashboards-verify`.
