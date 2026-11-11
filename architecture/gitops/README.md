# Configuration GitOps : un répertoire par groupe logique

`gitops/` contient toute la configuration déclarative du lab appliquée dans `k3s-01`, rangée par
**groupe logique** : chaque groupe réunit en un seul endroit ses objets Kubernetes, ses ressources
Crossplane (configuration des back-ends sur les VM), ses accès aux providers et ses Secrets
chiffrés. Chaque groupe est une Application Argo CD synchronisée depuis la branche `main` du
dépôt GitHub ([`argocd/`](argocd/README.md)) : un changement est appliqué une fois committé et
poussé. Ansible ne garde que l'installation des hôtes (OS, Podman, services, comptes
administrateurs).

```text
gitops/
├── argocd/          installation d'Argo CD et une Application par groupe (apps/)
├── crossplane/      socle : Crossplane (chart Helm), providers et fonctions (install/), API du lab (apis/), scripts des Secrets
├── cert-manager/    cert-manager (chart Helm) et émetteur autosigné ; les Certificate vivent dans leur groupe
├── otel-pipeline/   chaîne OTel : Kafka OTel, Service Edge, collecteurs de k3s-01
├── elastic/         plateforme Elastic : accès depuis k3s-01, Elasticsearch, Fleet, Kibana
├── supermarket/     exemple de groupe applicatif : 3 services Java et leurs bases
└── demo-api/        API de démonstration des signaux
```

Chaque groupe suit la même forme : un fichier par sujet (un back-end, une API), sa
`ClusterProviderConfig` dans le fichier du back-end qu'elle sert, `kustomization.yaml`, qui assemble
le tout, et `secrets/` : Secrets SOPS et générateur KSOPS, rendus par l'Application imbriquée
`<groupe>-secrets` (`secrets-app.yaml`). Les Secrets sont rendus à part parce que le kustomize de
l'image KSOPS (v5.3) ignore sans erreur les ressources dont le type finit par `List`, comme les
`AccessControlList` de provider-kafka ; le reste du groupe passe par le kustomize intégré d'Argo CD.

## Exemple : le groupe `supermarket`

Une application et ses bases de données forment un groupe :

| Fichier | Contenu | Cible |
|---|---|---|
| `namespace.yaml` | namespace `h0tl-supermarche-app` (jamais élagué) | k3s-01 |
| `applications.yaml` | 3 `Application` Crossplane : order, inventory et restock-service (Deployment, Service, agent OTel) | k3s-01 |
| `otel-agent.yaml` | configuration de l'agent Java OTel, recopiée par Kustomize dans `spec.otel.agentConfig` | k3s-01 |
| `postgresql.yaml` | `ClusterProviderConfig` postgresql, `pg_stat_statements` (2 bases), rôle `otel`, droits de supervision | PostgreSQL de supermarket-middleware-01 |
| `mongodb.yaml` | `ClusterProviderConfig` mongodb (Terraform `Kaginari/mongodb`), compte `otel_monitor` | MongoDB de supermarket-middleware-01 |
| `kafka-topics.yaml` | `ClusterProviderConfig` kafka-business, topics `supermarket.order.placed`, `supermarket.stock.depleted`, `supermarket.stock.restock-requested` | Kafka métier de supermarket-middleware-01 |
| `secrets/` | accès administrateur PostgreSQL, MongoDB et Kafka (crossplane-system) ; `postgresql-credentials` et `otel-edge-client-keys` des services (h0tl-supermarche-app) | k3s-01 |

Ajouter une application revient à créer un répertoire de groupe sur ce modèle (voir
[`apps/ADDING_APPLICATION.md`](../../apps/ADDING_APPLICATION.md)) et son Application Argo CD dans
`argocd/apps/`.

## Les autres groupes

| Groupe | Contenu | Remplace dans le lab |
|---|---|---|
| `crossplane` | Crossplane lui-même (`helm-release.yaml` : chart Helm officiel par une Application Argo CD imbriquée), cache des paquets, providers, fonctions et runtime (`install/`) ; XRD et Compositions des API `Application` (`apis/application`) et `OtelPlatform` (`apis/otel-platform` : 3 topics avec rétention et segments, ACL Write/Describe par publisher)  | `kubectl apply -k kubernetes/apps/*/default`, tâches `kafka-topics.sh` du rôle `otel_backend` |
| `otel-pipeline` | registre `OtelPlatform` (`platforms.yaml`, un document par plateforme, lu aussi par Ansible), comptes SCRAM `otel_publisher_<hôte>` et `otel_consumer` et ACL du collecteur backend (`kafka-accounts.yaml`), Service vers le Collecteur Edge (`edge-service.yaml`), collecteurs OTel de k3s-01 et leur RBAC (`kubernetes-collectors.yaml`), clés Bearer `otel-edge-client-keys` | `kafka-acls.sh`, comptes PLAIN de `kafka-jaas.conf.j2`, `kubectl apply -k` de la plateforme |
| `elastic` | namespace `elastic-stack`, Services vers elk-01 et IngressRoutes ; via Terraform `elastic/elasticstack` : ILM, templates et pipelines `@custom`, clé API `otel-collector-writer` publiée dans `elastic-stack/otel-elasticsearch-credentials` (`elasticsearch.yaml`), 11 packages et policies Fleet (`fleet.yaml`), data view APM (`kibana-saved-objects.yaml`), 4 règles d'alerte (`kibana-alerting.yaml`) ; via provider-http : 2 dashboards (`kibana-dashboards.yaml`) | `retention.py`, `sync-fleet-policies.sh`, `xpack.fleet.*` de `kibana.yml.j2`, `sync-observability-policies.sh`, `deploy-kibana-dashboard.sh` |
| `cert-manager` | cert-manager (`helm-release.yaml`, chart Helm officiel, CRD comprises) et `ClusterIssuer` autosigné `selfsigned` ; le certificat `elastic-public-tls` des IngressRoutes est déclaré dans `elastic/certificate.yaml` | certificat `openssl` de `make public-tls-apply` |
| `demo-api` | namespace `h0tl-demo-app`, `Application` demo-api et sa configuration d'agent, clé Bearer de l'Edge | `kubectl apply -k kubernetes/apps/demo-api/default` |

Les fichiers de `elastic/assets/` (ILM, pipelines, data view, règles, dashboards) sont la source de
vérité : Kustomize les publie tels quels dans le ConfigMap `elastic-assets`, que les Workspaces
Terraform lisent par variables `TF_VAR_*` (`spec.forProvider.env`), et recopie le JSON de chaque
dashboard dans le corps de sa `Request` (`replacements`). Le tableau `slos` de
`observability-policies.json` n'est pas déployé : les SLO ont été abandonnés (licence Platinum).

```text
k3s-01 : Argo CD ──▶ gitops/<groupe> ──▶ Crossplane                                            groupe
  provider-kafka ──── SASL/PLAIN otel_admin ──▶ Kafka OTel     otel-backend-01:9092           otel-pipeline
                 └─── PLAINTEXT ──────────────▶ Kafka métier   supermarket-middleware-01:9092 supermarket
  provider-sql ────── observability ───────────▶ PostgreSQL     supermarket-middleware-01:5432 supermarket
  provider-terraform (Kaginari/mongodb) ─ crossplane_admin ─▶ MongoDB  :27017                 supermarket
                     (elastic/elasticstack) ───▶ Elasticsearch, Kibana, Fleet   elk-01        elastic
  provider-http ───── Basic elastic ───────────▶ API Kibana (dashboards)                      elastic
  Composition Application ─────────────────────▶ Deployments, Services, ConfigMaps            supermarket, demo-api
```

## Secrets

Chaque groupe versionne ses Secrets chiffrés par SOPS avec age (`<groupe>/secrets/*.sops.yaml`,
règle dans `.sops.yaml` à la racine du dépôt) : seules les valeurs sont chiffrées. Le plugin
`ksops` d'Argo CD les déchiffre avec la clé age du Secret `argocd/sops-age`. Les valeurs viennent de
`.observability-credentials.env` (hors Git) : `crossplane/scripts/credentials.sh` les dérive, groupe
par groupe, et `crossplane/scripts/secrets.sh` les chiffre et tient à jour
`<groupe>/secrets/secret-generator.yaml`.

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
  image: {name: order-service, tag: 1.1.6}
  port: 3000
  probePath: /api/health          # sans valeur : sondes TCP
  otel:
    platform: supermarche         # platform.id (ADR-020) ; environment : homologation par défaut
    micrometerMetrics: true       # export OTLP Micrometer vers l'Edge
  env:                            # variables propres au service
    - {name: SPRING_KAFKA_BOOTSTRAP_SERVERS, value: "192.168.33.10:9092"}
```

Le `kustomization.yaml` du groupe recopie `otel-agent.yaml` (relu par `make trace-context-verify`)
dans `spec.otel.agentConfig`. La Composition produit `<application>-otel-agent-config`, le
Deployment et le Service ; l'empreinte de la configuration de l'agent, posée sur le gabarit des
pods, les redémarre quand elle change. Le tag déployé est celui du dépôt : `APP_IMAGE_TAG` et
`DEMO_API_IMAGE_TAG`, utilisés pour construire et importer les images, doivent lui correspondre.

## Élagage et caches

Argo CD élague (`prune`) les ressources retirées du dépôt, y compris les `Application` ; leurs objets
composés disparaissent avec elles. Les namespaces portent `Delete=false` et ne sont jamais élagués.

provider-terraform garde ses providers Terraform (`TF_PLUGIN_CACHE_DIR`) et Crossplane ses paquets
(`packageCache.pvc`, `crossplane/install/package-cache.yaml`) dans le cache local de l'hôte monté sur
`k3s-01` (`/var/cache/lab`, voir le README de l'architecture).

## Ce qui reste impératif, et pourquoi

| Élément | Raison |
|---|---|
| `make argocd-install`, `make crossplane-ca-apply` | Amorçage : Argo CD, la clé age et le bundle CA du poste (proxy TLS d'entreprise) doivent exister avant toute synchronisation. Tout le reste, Crossplane et cert-manager compris, est installé par Argo CD. |
| `make secrets-encrypt` | Les identifiants sont générés localement : il faut rechiffrer puis committer quand ils changent. |
| `otel_admin`, `observability`, `elastic`, `kibana_system`, `crossplane_admin` (MongoDB) | Comptes créés au démarrage des services par Ansible ; ce sont eux que Crossplane utilise. Le provider `Kaginari/mongodb` s'authentifie toujours : il ne peut pas créer le premier compte. |
| Migration ILM des indices existants (`make ilm-deploy`), suppression des data streams obsolètes | Opérations ponctuelles sur des données, pas un état cible. |
| Doublons Fleet Server et clé d'enrôlement (`bootstrap-fleet-policies.sh`) | Opérations d'exécution sur des agents enrôlés. |
| Construction et import des images (`make apps-build`, `images-import`) | Pas d'état à réconcilier ; l'`Application` fixe le tag à déployer. |

## Mots de passe

Les comptes SCRAM Kafka reprennent la dérivation du lab : `sha256(KAFKA_OTEL_PUBLISHER_PASSWORD:<compte>)`.
Ansible configure les clients des VM avec ces mots de passe, Crossplane crée les comptes, et les deux
partagent les mêmes valeurs sans échange entre eux. Le compte MongoDB `crossplane_admin` suit la même
règle avec `sha256(MONGODB_PASSWORD:crossplane_admin)` ; `otel_monitor` garde `MONGODB_PASSWORD`.

## Commandes

```bash
make kubernetes-validate           # rendu de chaque groupe (ksops et clé age requis : brew install ksops)
make crossplane-apply              # Argo CD, bundle CA, puis tous les groupes depuis GitHub (Crossplane compris)
make crossplane-install            # attendre Crossplane, ses providers et ses fonctions (installés par Argo CD)
make argocd-sync                   # relire le dépôt sans attendre (ARGOCD_APP=<groupe> pour un seul)
make argocd-status                 # état de synchronisation et de santé de chaque groupe
make crossplane-status             # ressources gérées, Application, Argo CD
make crossplane-platforms-apply    # après push de otel-pipeline/platforms.yaml : relecture, attente de Kafka
make apps-deploy                   # attendre le groupe supermarket et les rollouts
make demo-api-deploy               # attendre le groupe demo-api
```

Ajouter une plateforme OTel revient à ajouter un document dans `otel-pipeline/platforms.yaml`, à
committer et pousser, puis à lancer `make crossplane-platforms-apply`. Le collecteur backend découvre
les nouveaux topics par expression régulière, et l'Edge prend la plateforme en compte à son prochain
provisionnement.
