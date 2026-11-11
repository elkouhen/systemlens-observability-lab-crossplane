# Couche Crossplane

Crossplane v2 tourne dans `k3s-01`. Il **déclare et réconcilie en continu** la configuration des back-ends
du lab et les objets Kubernetes de `k3s-01`. Avant, cette configuration était appliquée de façon impérative
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
  provider-kubernetes ── ServiceAccount ───────▶ API k3s-01 (namespaces, Secrets, plateforme)
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
| `scripts/kibana-requests.py` (généré) | dashboards `business-metrics-dashboard` et `otel-flow-health` | `deploy-kibana-dashboard.sh`, `replace-kibana-dashboard.sh` |
| `kubernetes/secrets.yaml` | namespaces `h0tl-supermarche-app` et `h0tl-demo-app` ; Secrets `otel-edge-client-keys` (3 namespaces), `postgresql-credentials`, `postgresql-fleet-credentials`, `elasticsearch-es-elastic-user`, copiés depuis `crossplane-system/lab-secrets` et recréés s'ils disparaissent | cibles `otel-edge-client-keys-apply`, `postgresql-credentials-apply` et `kubectl create secret` de `elk-deploy` |
| `scripts/kubernetes-objects.py` (généré) | un `Object` par objet de `platform/kubernetes/overlays/local` (18 : namespace, Services et EndpointSlices vers les VM, IngressRoutes, collecteurs OTel, RBAC), réaligné par watch | `kubectl apply -k platform/kubernetes/overlays/local` |
| `applications/definition.yaml`, `composition.yaml` | API `Application` (namespacée) : ConfigMap de l'agent OTel, Deployment et Service d'un service Java instrumenté | `kubectl apply -k kubernetes/apps/*/default` et `kubectl set image` de `apps-deploy` et `demo-api-deploy` |

Les fichiers JSON et NDJSON de `platform/elk/` restent la source de vérité. `scripts/assets.sh` les publie
tels quels dans le ConfigMap `elastic-assets` lu par Terraform (dont les règles d'alerte). Le tableau `slos`
de `observability-policies.json` n'est plus déployé : les SLO ont été abandonnés (l'API exige une licence
Platinum). `scripts/kibana-requests.py` embarque les dashboards dans les ressources `Request`.

Les manifests Kustomize de `platform/kubernetes` restent la source des objets de la plateforme :
`scripts/kubernetes-objects.py` enveloppe la sortie de `kubectl kustomize` dans des `Object`. Le namespace
`elastic-stack` et les namespaces applicatifs ne sont jamais supprimés par Crossplane (pas de politique
`Delete`). provider-kubernetes applique en server-side apply : un champ déclaré modifié à la main est
réaligné ; un champ ajouté par un autre gestionnaire (par exemple l'annotation de `kubectl rollout restart`)
est conservé.

## Élagage et caches

`make crossplane-kubernetes-apply`, `make apps-deploy` et `make demo-api-deploy` appliquent leur rendu
puis lancent `scripts/prune.py` : les `Object` (label `lab.io/managed-by: kubernetes-objects`) et les
`Application` (label `lab.io/managed-by: applications`) absents du rendu sont supprimés, ce qui
supprime aussi les objets qu'ils gèrent. L'élagage se limite aux namespaces présents dans le rendu.

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
    agentConfigFile: default/otel/agent.yaml
  env:                            # variables propres au service
    - {name: SPRING_KAFKA_BOOTSTRAP_SERVERS, value: "192.168.33.10:9092"}
```

`scripts/applications.py` remplace `agentConfigFile` par le contenu du fichier (qui reste la source, relue
par `make trace-context-verify`) et fixe le tag (`APP_IMAGE_TAG`, `DEMO_API_IMAGE_TAG`). La Composition
produit `<application>-otel-agent-config`, le Deployment et le Service avec les noms, labels, sondes et
variables du lab ; l'empreinte de la configuration de l'agent, posée sur le gabarit des pods, les redémarre
quand elle change. Changer le tag d'une `Application` redéploie le service.

## Ce qui reste impératif, et pourquoi

| Élément | Raison |
|---|---|
| `scripts/credentials.sh` : Secrets d'accès des providers et Secret source `lab-secrets` | Amorçage : il faut bien fournir à Crossplane ses identifiants administrateur et les secrets des workloads. Ils sont dérivés de `.observability-credentials.env`. Un gestionnaire de secrets (External Secrets, Vault) pourrait prendre le relais. |
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
make crossplane-credentials-apply  # Secrets d'accès des providers et Secret source lab-secrets
make crossplane-apply              # toute la configuration, objets Kubernetes compris
make crossplane-kubernetes-apply   # après modification de platform/kubernetes
make crossplane-status             # état des ressources gérées et des Application
make crossplane-platforms-apply    # après modification de platforms.yaml
make apps-deploy                   # Application supermarket-demo (APP_IMAGE_TAG)
make demo-api-deploy               # Application demo-api (DEMO_API_IMAGE_TAG)
```

Ajouter une plateforme OTel revient à ajouter un document dans `platforms.yaml`, puis à lancer
`make crossplane-platforms-apply`. Le collecteur backend découvre les nouveaux topics par expression
régulière, et l'Edge prend la plateforme en compte à son prochain provisionnement.
