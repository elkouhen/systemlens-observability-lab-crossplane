# Configuration GitOps : un répertoire par groupe logique

`gitops/` contient toute la configuration déclarative du lab, rangée par **groupe logique** :
chaque groupe réunit en un seul endroit ses objets Kubernetes, ses ressources Crossplane, ses accès
aux providers et ses Secrets chiffrés. Chaque groupe est une Application Argo CD synchronisée dans
le cluster de gestion **`tools-01`** (le hub) depuis la branche `main` du dépôt GitHub
([`argocd/`](argocd/README.md)) : un changement est appliqué une fois committé et poussé. Ansible ne
garde que l'installation des hôtes (OS, k3s, Edge, agents EDOT).

```text
                tools-01 (hub) : Argo CD, Crossplane, cert-manager, clé age
                 │ Argo CD (Helm, manifests)        │ Crossplane (provider-kubernetes, Object)
                 ▼                                  ▼
   k3s-01 (applicatif)                       elk-01 (observabilité)
   opérateurs CloudNativePG, Strimzi,        opérateur ECK
   MongoDB ; services Java, PostgreSQL,      Elasticsearch, Kibana, Fleet Server 9.5.4
   MongoDB, Kafka métier et OTel,            (Services LoadBalancer 192.168.33.40:9200/5601/8220)
   collecteurs OTel (NodePort 192.168.33.50)
```

```text
gitops/
├── argocd/          installation d'Argo CD (hub) et une Application par groupe (apps/)
├── crossplane/      socle : Crossplane (chart Helm), providers et fonctions, clusters cibles (install/),
│                    API du lab (apis/), scripts des Secrets
├── cert-manager/    cert-manager (chart Helm) et émetteur autosigné, dans le hub
├── operators/       opérateurs des clusters cibles (charts Helm) : CloudNativePG, Strimzi, MongoDB, ECK
├── otel-pipeline/   chaîne OTel : Kafka OTel, plateformes, comptes et ACL ; k3s-01/ : collecteurs
├── elastic/         plateforme Elastic : ObservabilityStack (ECK), Elasticsearch, Fleet, Kibana
├── supermarket/     exemple de groupe applicatif : 3 services Java et leurs bases
└── demo-api/        API de démonstration des signaux
```

Chaque groupe suit la même forme : un fichier par sujet (une instance, un back-end, une API), la
`ClusterProviderConfig` d'un back-end dans le fichier qu'elle sert, `kustomization.yaml` qui
assemble le tout, et `secrets/` : Secrets SOPS et générateur KSOPS, rendus dans le hub par
l'Application imbriquée `<groupe>-secrets` (`secrets-app.yaml`). Les Secrets sont rendus à part
parce que le kustomize de l'image KSOPS (v5.3) ignore sans erreur les ressources dont le type finit
par `List`, comme les `AccessControlList` de provider-kafka ; le reste du groupe passe par le
kustomize intégré d'Argo CD. Un groupe peut avoir un sous-répertoire du nom d'un cluster cible
(`otel-pipeline/k3s-01/`) : ces manifests sont synchronisés directement dans ce cluster par une
Application imbriquée `<groupe>-<cluster>`.

## Ce que fait Crossplane depuis le hub

| Mécanisme | Cible | Exemples |
|---|---|---|
| API du lab composées en `Object` de provider-kubernetes (une `ClusterProviderConfig` par cluster : `crossplane/install/clusters.yaml`) | objets des clusters cibles | `Application` → Deployment, Service, ConfigMap ; `PostgreSQLInstance` → Cluster CloudNativePG ; `MongoDBInstance` → MongoDBCommunity ; `KafkaCluster` → Kafka et KafkaNodePool Strimzi ; `ObservabilityStack` → Elasticsearch, Kibana, Agent ECK |
| `Object` avec `references.patchesFrom` | Secrets des clusters cibles, valeurs lues dans les Secrets du hub | clés Bearer de l'Edge, comptes de supervision, clé API du collecteur backend |
| provider-kafka, provider-sql, provider-terraform, provider-http | back-ends, par leurs points d'accès réseau | topics, comptes SCRAM et ACL ; rôles et droits PostgreSQL ; compte MongoDB `otel_monitor` ; ILM, Fleet, Kibana |

Les instances sont déclarées dans le groupe qui les utilise, dans un namespace du hub qui porte
aussi leurs mots de passe (Secrets SOPS) ; leurs objets sont composés dans le **même namespace** du
cluster cible (`spec.cluster`, `k3s-01` par défaut, `elk-01` pour `ObservabilityStack`).

## Exemple : le groupe `supermarket`

Une application et ses bases de données forment un groupe :

| Fichier | Contenu | Cible |
|---|---|---|
| `namespace.yaml` | namespace `h0tl-supermarche-app` du hub (jamais élagué) | hub |
| `target.yaml` | `Object` : namespace `h0tl-supermarche-app` de k3s-01, clé Bearer de l'Edge des pods | k3s-01 |
| `databases.yaml` | `PostgreSQLInstance` (NodePort 30432), `MongoDBInstance` (comptes `crossplane_admin` et `observability`, NodePort 30017), `KafkaCluster` métier sans authentification (NodePort 31192) | k3s-01 |
| `applications.yaml` | 3 `Application` Crossplane : order, inventory et restock-service (Deployment, Service, agent OTel), raccordées aux Services des instances | k3s-01 |
| `otel-agent.yaml` | configuration de l'agent Java OTel, recopiée par Kustomize dans `spec.otel.agentConfig` | k3s-01 |
| `postgresql.yaml` | `ClusterProviderConfig` postgresql (`postgres` par 192.168.33.50:30432), `pg_stat_statements` (2 bases), rôle `otel`, droits de supervision | PostgreSQL de k3s-01 |
| `mongodb.yaml` | `ClusterProviderConfig` mongodb (Terraform `Kaginari/mongodb`, 192.168.33.50:30017), compte `otel_monitor` | MongoDB de k3s-01 |
| `kafka-topics.yaml` | `ClusterProviderConfig` kafka-business (192.168.33.50:31192), topics `supermarket.order.placed`, `supermarket.stock.depleted`, `supermarket.stock.restock-requested` | Kafka métier de k3s-01 |
| `secrets/` | accès du hub aux bases et à Kafka (crossplane-system) ; mots de passe des instances et clé Bearer de l'Edge (h0tl-supermarche-app) | hub |

Ajouter une application revient à créer un répertoire de groupe sur ce modèle (voir
[`apps/ADDING_APPLICATION.md`](../../apps/ADDING_APPLICATION.md)) et son Application Argo CD dans
`argocd/apps/`.

## Les autres groupes

| Groupe | Contenu |
|---|---|
| `crossplane` | Crossplane lui-même (`helm-release.yaml`), cache des paquets, providers (kafka, sql, terraform, http, kubernetes), fonctions, runtime et clusters cibles (`install/`) ; XRD et Compositions des API `Application`, `OtelPlatform` (3 topics avec rétention et segments, ACL Write/Describe par publisher), `PostgreSQLInstance`, `MongoDBInstance`, `KafkaCluster` et `ObservabilityStack` (`apis/`) |
| `cert-manager` | cert-manager (`helm-release.yaml`, chart Helm officiel, CRD comprises) et `ClusterIssuer` autosigné `selfsigned`, dans le hub |
| `operators` | une Application Argo CD par chart Helm, synchronisée dans son cluster cible : CloudNativePG 1.30.1 (chart 0.29.1), Strimzi 1.3.1 et MongoDB Controllers for Kubernetes 1.15.0 dans k3s-01, ECK 3.5.0 dans elk-01 (images arm64 vérifiées) |
| `otel-pipeline` | `KafkaCluster` otel-kafka (SCRAM, ACL, administrateur `otel-admin`, NodePort 31092 pour l'Edge et le hub) et sa `ClusterProviderConfig` (`kafka.yaml`) ; registre `OtelPlatform` (`platforms.yaml`, lu aussi par Ansible) ; comptes SCRAM `otel_publisher_otel_edge_01` et `otel_consumer` et ACL (`kafka-accounts.yaml`) ; Secrets des collecteurs recopiés dans k3s-01 (`target.yaml`) ; `k3s-01/` : Service vers le Collecteur Edge, collecteurs Kubernetes, collecteur backend (Kafka OTel → Elasticsearch) et collecteur `otel-middleware` (supervision de PostgreSQL, MongoDB et des deux Kafka) |
| `elastic` | `ObservabilityStack` elastic (`stack.yaml` : Elasticsearch, Kibana et Fleet Server ECK dans elk-01, en HTTP, mot de passe `elastic` du Secret SOPS) ; via Terraform `elastic/elasticstack` : ILM, templates et pipelines `@custom`, clé API `otel-collector-writer` publiée dans `elastic-stack/otel-elasticsearch-credentials` du hub (`elasticsearch.yaml`), 11 packages et policies Fleet (`fleet.yaml`), data view APM (`kibana-saved-objects.yaml`), 4 règles d'alerte (`kibana-alerting.yaml`) ; via provider-http : 2 dashboards (`kibana-dashboards.yaml`) |
| `demo-api` | namespace `h0tl-demo-app` (hub et k3s-01), `Application` demo-api et sa configuration d'agent, clé Bearer de l'Edge |

Les fichiers de `elastic/assets/` (ILM, pipelines, data view, règles, dashboards) sont la source de
vérité : Kustomize les publie tels quels dans le ConfigMap `elastic-assets`, que les Workspaces
Terraform lisent par variables `TF_VAR_*` (`spec.forProvider.env`), et recopie le JSON de chaque
dashboard dans le corps de sa `Request` (`replacements`). Le tableau `slos` de
`observability-policies.json` n'est pas déployé : les SLO ont été abandonnés (licence Platinum).

```text
tools-01 : Argo CD ──▶ gitops/<groupe> ──▶ Crossplane                                         groupe
  provider-kubernetes ── Object ────────────▶ k3s-01, elk-01 (instances, services, Secrets)   tous
  provider-kafka ──── SCRAM otel-admin ─────▶ Kafka OTel     192.168.33.50:31092              otel-pipeline
                 └─── PLAINTEXT ────────────▶ Kafka métier   192.168.33.50:31192              supermarket
  provider-sql ────── postgres ─────────────▶ PostgreSQL     192.168.33.50:30432              supermarket
  provider-terraform (Kaginari/mongodb) ─ crossplane_admin ─▶ MongoDB 192.168.33.50:30017     supermarket
                     (elastic/elasticstack) ─▶ Elasticsearch, Kibana, Fleet 192.168.33.40      elastic
  provider-http ───── Basic elastic ────────▶ API Kibana (dashboards)                         elastic
```

## Secrets

Chaque groupe versionne ses Secrets chiffrés par SOPS avec age (`<groupe>/secrets/*.sops.yaml`,
règle dans `.sops.yaml` à la racine du dépôt) : seules les valeurs sont chiffrées. Le plugin
`ksops` d'Argo CD les déchiffre dans le hub avec la clé age du Secret `argocd/sops-age`. Les valeurs
viennent de `.observability-credentials.env` (hors Git) : `crossplane/scripts/credentials.sh` les
dérive, groupe par groupe, et `crossplane/scripts/secrets.sh` les chiffre et tient à jour
`<groupe>/secrets/secret-generator.yaml`. Un pod d'un cluster cible ne lit jamais un Secret du hub :
les valeurs nécessaires sont recopiées par un `Object` (`references.patchesFrom`, résolues dans le
hub par provider-kubernetes).

```bash
make secrets-encrypt   # après un changement des identifiants : rechiffre les Secrets modifiés
git add architecture/gitops && git commit && git push
```

`make argocd-apps-apply` refuse de continuer si un Secret chiffré ne correspond plus aux
identifiants locaux (`make secrets-check`).

## Applications

Une application est déclarée dans son groupe :

```yaml
apiVersion: apps.lab.io/v1alpha1
kind: Application
metadata: {name: order-service, namespace: h0tl-supermarche-app}
spec:
  image: {name: order-service, tag: 1.1.6}   # registry : GHCR du dépôt par défaut
  port: 3000
  probePath: /api/health          # sans valeur : sondes TCP
  # cluster: k3s-01               # cluster cible, par défaut
  otel:
    platform: supermarche         # platform.id (ADR-020) ; environment : homologation par défaut
    micrometerMetrics: true       # export OTLP Micrometer vers l'Edge
  env:                            # variables propres au service
    - {name: SPRING_KAFKA_BOOTSTRAP_SERVERS, value: "supermarket-kafka-kafka-bootstrap:9092"}
```

Le `kustomization.yaml` du groupe recopie `otel-agent.yaml` (relu par `make trace-context-verify`)
dans `spec.otel.agentConfig`. La Composition produit, dans le cluster cible, `<application>-otel-agent-config`,
le Deployment et le Service ; l'empreinte de la configuration de l'agent, posée sur le gabarit des
pods, les redémarre quand elle change. L'image est
`<registry>/<name>:<tag>`, `registry` valant par défaut
`ghcr.io/elkouhen/systemlens-observability-lab-crossplane`, où le workflow GitHub
`build-images.yml` publie les images au tag déclaré ici. Livrer une version : changer le code, changer
le tag ici, pousser ; GitHub construit, Argo CD déploie (voir `apps/README.md`).

## Élagage et caches

Argo CD élague (`prune`) les ressources retirées du dépôt, y compris les `Application` ; leurs objets
composés disparaissent avec elles, dans les clusters cibles aussi. Les namespaces portent
`Delete=false` et ne sont jamais élagués ; ceux des clusters cibles sont des `Object` sans politique
`Delete`.

provider-terraform garde ses providers Terraform (`TF_PLUGIN_CACHE_DIR`) et Crossplane ses paquets
(`packageCache.pvc`, `crossplane/install/package-cache.yaml`) dans le cache local de l'hôte monté sur
`tools-01` (`/var/cache/lab`, voir le README de l'architecture).

## Ce qui reste impératif, et pourquoi

| Élément | Raison |
|---|---|
| `make argocd-install`, `make crossplane-ca-apply`, `make clusters-register` | Amorçage : Argo CD, la clé age, le bundle CA du poste (proxy TLS d'entreprise) et les identifiants des clusters cibles (régénérés par k3s à chaque installation) doivent exister avant toute synchronisation. Tout le reste, Crossplane, cert-manager et les opérateurs compris, est installé par Argo CD. |
| `make secrets-encrypt` | Les identifiants sont générés localement : il faut rechiffrer puis committer quand ils changent. |
| Migration ILM des indices existants (`make ilm-deploy`), suppression des data streams obsolètes | Opérations ponctuelles sur des données, pas un état cible. |
| Doublons Fleet Server et clé d'enrôlement (`bootstrap-fleet-policies.sh`) | Opérations d'exécution sur des agents enrôlés. |
| Construction des images (workflow GitHub `build-images.yml`, `make images-wait`) | Hors cluster : GitHub publie sur GHCR le tag fixé par l'`Application`. |

Les comptes d'amorçage des back-ends sont désormais déclarés : `postgres` (superutilisateur de la
`PostgreSQLInstance`), `crossplane_admin` (compte de la `MongoDBInstance`), `otel-admin` (`KafkaUser`
de la `KafkaCluster`, super-utilisateur) et `elastic` (fichier d'utilisateurs de
l'`ObservabilityStack`).

## Mots de passe

Les comptes SCRAM Kafka reprennent la dérivation du lab : `sha256(KAFKA_OTEL_PUBLISHER_PASSWORD:<compte>)`,
pour `otel_publisher_<hôte>` comme pour l'administrateur `otel-admin`. Ansible configure l'Edge avec
ces mots de passe, Crossplane crée les comptes, et les deux partagent les mêmes valeurs sans échange
entre eux. Le compte MongoDB `crossplane_admin` suit la même règle avec
`sha256(MONGODB_PASSWORD:crossplane_admin)` ; `otel_monitor` et `observability` gardent
`MONGODB_PASSWORD`, `postgres`, `observability` et `otel` (PostgreSQL) `POSTGRESQL_PASSWORD`.

L'opérateur d'utilisateurs de Strimzi supprime les comptes qu'il ne gère pas : il ignore ceux dont
le nom commence par `otel_` (`ignoredUsersPattern` de l'API `KafkaCluster`), qui restent à
provider-kafka.

## Commandes

```bash
make kubernetes-validate           # rendu de chaque groupe (ksops et clé age requis : brew install ksops)
make crossplane-apply              # Argo CD dans le hub, bundle CA, clusters cibles, puis tous les groupes
make crossplane-install            # attendre Crossplane, ses providers et ses fonctions (installés par Argo CD)
make operators-wait                # attendre les opérateurs des clusters cibles
make data-services-wait            # attendre PostgreSQLInstance, MongoDBInstance et KafkaCluster
make elastic-stack-wait            # attendre Elasticsearch et Kibana de l'ObservabilityStack
make argocd-sync                   # relire le dépôt sans attendre (ARGOCD_APP=<groupe> pour un seul)
make argocd-status                 # état de synchronisation et de santé de chaque groupe
make crossplane-status             # ressources gérées, instances des API, Argo CD
make crossplane-platforms-apply    # après push de otel-pipeline/platforms.yaml : relecture, attente de Kafka
make apps-deploy                   # attendre le groupe supermarket et les rollouts dans k3s-01
make demo-api-deploy               # attendre le groupe demo-api
```

Ajouter une plateforme OTel revient à ajouter un document dans `otel-pipeline/platforms.yaml`, à
committer et pousser, puis à lancer `make crossplane-platforms-apply`. Le collecteur backend découvre
les nouveaux topics par expression régulière, et l'Edge prend la plateforme en compte à son prochain
provisionnement.
