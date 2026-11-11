# Couche Crossplane

Crossplane v2 tourne dans `k3s-01`. Il **déclare et réconcilie en continu** la configuration des back-ends
du lab et les objets Kubernetes de `k3s-01`. Ces déclarations sont synchronisées depuis GitHub par
Argo CD ([`../argocd`](../argocd/README.md)) : un changement est appliqué une fois committé et poussé. Avant, cette configuration était appliquée de façon impérative
par Ansible (`podman exec kafka-*.sh`, `psql`, `mongosh`), par des scripts `curl`, par la préconfiguration
de Kibana et par `kubectl apply -k` / `kubectl create secret`. Ansible ne garde plus que l'installation des
hôtes : OS, Podman, binaires, services et amorçage des comptes administrateurs.

```text
k3s-01 : Crossplane
  provider-kafka ──── SASL/PLAIN otel_admin ──▶ Kafka OTel     otel-backend-01:9092
                 └─── PLAINTEXT ──────────────▶ Kafka métier   supermarket-middleware-01:9092
  provider-sql ────── observability ───────────▶ PostgreSQL     supermarket-middleware-01:5432
  provider-terraform (elastic/elasticstack) ───▶ Elasticsearch, Kibana, Fleet   elk-01
                     (Kaginari/mongodb) ─ crossplane_admin ─▶ MongoDB  supermarket-middleware-01:27017
  provider-http ───── Basic elastic ───────────▶ API Kibana (dashboards)
  provider-kubernetes ── ServiceAccount ───────▶ API k3s-01 (namespaces applicatifs, Secrets)
  Composition Application ─────────────────────▶ Deployments, Services, ConfigMaps des applications
```

## Ce qui est géré

| Fichier | Ressources | Remplace dans le lab |
|---|---|---|
| `platforms.yaml` | registre `OtelPlatform`, un document par plateforme | `otel_platforms` dans `group_vars/all.yml`, désormais lu depuis ce fichier |
| `kafka-otel/definition.yaml`, `composition.yaml` | par plateforme : 3 `Topic` (rétention, segments) et des ACL Write/Describe pour chaque publisher | tâches `kafka-topics.sh`, `kafka-configs.sh` et `kafka-acls.sh` du rôle `otel_backend`, et rétention OTel de `retention.yml` |
| `kafka-otel/accounts.yaml` | comptes SCRAM `otel_publisher_<hôte>` et `otel_consumer`, ACL du collecteur backend | comptes PLAIN codés en dur dans `kafka-jaas.conf.j2` |
| `kafka-business/topics.yaml` | `supermarket.order.placed`, `supermarket.stock.depleted`, `supermarket.stock.restock-requested` | Job Kubernetes `otel-telemetry-topics` et rétention métier de `retention.yml` |
| `postgresql/monitoring.yaml` | `pg_stat_statements` (2 bases), rôle `otel`, `pg_monitor`, SELECT sur les vues de statistiques | `podman exec psql` du rôle `supermarket_middleware` |
| `mongodb/monitoring.yaml` | compte `otel_monitor` (rôle `clusterMonitor` sur `admin`), recréé s'il disparaît | `podman exec mongosh` du rôle `supermarket_middleware` et redémarrage de l'agent EDOT qui en dépendait |
| `elastic/elasticsearch.yaml` | ILM `supermarket-middleware-observability-24h`, `{logs,metrics,traces}@custom`, 12 pipelines `@custom` Kafka et MongoDB, clé API `otel-collector-writer` publiée dans `elastic-stack/otel-elasticsearch-credentials` | `retention.py` (politique et templates), `sync-fleet-policies.sh`, cible `otel-elasticsearch-credentials-apply` |
| `elastic/fleet.yaml` | 11 packages d'intégration, hôte Fleet Server, policies `eck-fleet-server` (avec `fleet-server-1`) et `otel-fleet` | `xpack.fleet.*` dans `kibana.yml.j2`, installations de `bootstrap-fleet-policies.sh` |
| `elastic/kibana.yaml` | data view APM (import NDJSON) | `make apm-data-view-deploy` |
| `elastic/kibana-alerting.yaml` | 4 règles d'alerte (`elasticstack_kibana_alerting_rule`), réalignées si on les modifie dans Kibana | `sync-observability-policies.sh`, puis les `Request` provider-http des règles |
| `elastic/dashboards.yaml` | dashboards `business-metrics-dashboard` et `otel-flow-health-dashboard` (provider-http) | `deploy-kibana-dashboard.sh`, `replace-kibana-dashboard.sh` |
| `kubernetes/secrets.yaml` | namespaces `h0tl-supermarche-app` et `h0tl-demo-app` ; Secrets `otel-edge-client-keys` (3 namespaces), `postgresql-credentials`, `postgresql-fleet-credentials`, `elasticsearch-es-elastic-user`, copiés depuis `crossplane-system/lab-secrets` et recréés s'ils disparaissent | cibles `otel-edge-client-keys-apply`, `postgresql-credentials-apply` et `kubectl create secret` de `elk-deploy` |
| `secrets/*.sops.yaml` | Secrets d'accès des providers et Secret source `lab-secrets`, chiffrés par SOPS (age), déchiffrés par KSOPS dans Argo CD | `kubectl create secret` des identifiants administrateur |
| `applications/definition.yaml`, `composition.yaml` | API `Application` (namespacée) : ConfigMap de l'agent OTel, Deployment et Service d'un service Java instrumenté | `kubectl apply -k kubernetes/apps/*/default` et `kubectl set image` de `apps-deploy` et `demo-api-deploy` |

Les objets Kubernetes de la plateforme (`platform/kubernetes/overlays/local` : namespace
`elastic-stack`, Services et EndpointSlices vers les VM, IngressRoutes, collecteurs OTel, RBAC) sont
synchronisés directement par Argo CD (Application `platform-kubernetes`), sans passer par des `Object`
Crossplane : Argo CD réaligne déjà en continu les objets Kubernetes natifs.

`kustomization.yaml` assemble ces déclarations pour Argo CD (Application `crossplane-config`). Les
fichiers JSON et NDJSON de `platform/elk/` restent la source de vérité : Kustomize les publie tels
quels dans le ConfigMap `elastic-assets`, que les Workspaces Terraform lisent par variables
`TF_VAR_*` (`spec.forProvider.env`), et recopie le JSON de chaque dashboard dans le corps de sa
`Request` (`replacements`). Le tableau `slos` de `observability-policies.json` n'est pas déployé :
les SLO ont été abandonnés (l'API exige une licence Platinum). Ces fichiers sont hors du répertoire
de l'application : la lecture est autorisée par `--load-restrictor LoadRestrictionsNone` (`argocd-cm`
et `make kubernetes-validate`).

Le namespace `elastic-stack` et les namespaces applicatifs ne sont jamais supprimés (pas de politique
`Delete` pour Crossplane, `Delete=false` pour Argo CD). provider-kubernetes applique en server-side
apply : un champ déclaré modifié à la main est réaligné ; un champ ajouté par un autre gestionnaire
(par exemple l'annotation de `kubectl rollout restart`) est conservé.

## Élagage et caches

Argo CD élague (`prune`) les ressources retirées du dépôt, y compris les `Application` ; leurs objets
composés disparaissent avec elles.

provider-terraform garde ses providers Terraform (`TF_PLUGIN_CACHE_DIR`) et Crossplane ses paquets
(`packageCache.pvc`, `install/package-cache.yaml`) dans le cache local de l'hôte monté sur `k3s-01`
(`/var/cache/lab`, voir le README de l'architecture) : une reconstruction ne les retélécharge pas.

## Applications

Une application est déclarée par `kubernetes/apps/<application>/application.yaml` :

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

Le `kustomization.yaml` du même répertoire recopie `default/otel/agent.yaml` (qui reste la source,
relue par `make trace-context-verify`) dans `spec.otel.agentConfig`. Le tag déployé est celui du
dépôt : `APP_IMAGE_TAG` et `DEMO_API_IMAGE_TAG`, utilisés pour construire et importer les images,
doivent lui correspondre. La Composition
produit `<application>-otel-agent-config`, le Deployment et le Service avec les noms, labels, sondes et
variables du lab ; l'empreinte de la configuration de l'agent, posée sur le gabarit des pods, les redémarre
quand elle change. Changer le tag d'une `Application`, committer et pousser redéploie le service.

## Ce qui reste impératif, et pourquoi

| Élément | Raison |
|---|---|
| `make secrets-encrypt` (`scripts/secrets.sh`, `scripts/credentials.sh`) | Les valeurs viennent de `.observability-credentials.env`, généré localement : il faut les rechiffrer (SOPS, age) puis committer quand il change. `make argocd-apps-apply` vérifie qu'ils correspondent (`make secrets-check`). |
| `make crossplane-install`, `make argocd-install` | Amorçage : Crossplane (Helm), ses paquets, Argo CD et la clé age ne peuvent pas se synchroniser eux-mêmes avant d'exister. |
| `otel_admin`, `observability`, `elastic`, `kibana_system`, `crossplane_admin` (MongoDB) | Comptes créés au démarrage des services par Ansible. Ce sont eux que Crossplane utilise. MongoDB tourne sans `--auth`, mais le provider Terraform `Kaginari/mongodb` s'authentifie toujours : il ne peut pas créer le premier compte. |
| Secret TLS `elastic-public-tls` (`make public-tls-apply`) | Certificat autosigné généré localement par `openssl`. |
| Migration ILM des indices existants (`make ilm-deploy`) et suppression des data streams obsolètes | Opérations ponctuelles sur des données, pas un état cible. |
| Doublons Fleet Server et clé d'enrôlement (`bootstrap-fleet-policies.sh`) | Opérations d'exécution sur des agents enrôlés. |
| Construction et import des images (`make apps-build`, `images-import`) | Pas d'état à réconcilier ; l'`Application` fixe le tag à déployer. |

## Mots de passe

Les comptes SCRAM Kafka reprennent la dérivation du lab : `sha256(KAFKA_OTEL_PUBLISHER_PASSWORD:<compte>)`.
Ansible configure les clients des VM (Edge, backend, agents EDOT) avec ces mots de passe, Crossplane crée
les comptes, et les deux partagent les mêmes valeurs sans échange entre eux. Le compte MongoDB
`crossplane_admin` suit la même règle avec `sha256(MONGODB_PASSWORD:crossplane_admin)` ; `otel_monitor`
garde `MONGODB_PASSWORD`, lu par les agents EDOT.

## Commandes

```bash
make crossplane-install            # Crossplane, providers et fonctions (avec le bundle CA de k3s-01)
make secrets-encrypt               # rechiffrer les Secrets après changement des identifiants (puis commit, push)
make crossplane-apply              # Argo CD, puis toute la configuration depuis GitHub
make argocd-sync                   # relire le dépôt sans attendre (ARGOCD_APP=<nom> pour une seule)
make crossplane-status             # état des ressources gérées, des Application et d'Argo CD
make crossplane-platforms-apply    # après push de platforms.yaml : relecture et attente de Kafka
make apps-deploy                   # attendre l'Application supermarket-demo et ses rollouts
make demo-api-deploy               # attendre l'Application demo-api
```

Ajouter une plateforme OTel revient à ajouter un document dans `platforms.yaml`, à committer et
pousser, puis à lancer `make crossplane-platforms-apply`. Le collecteur backend découvre les nouveaux topics par expression
régulière, et l'Edge prend la plateforme en compte à son prochain provisionnement.
