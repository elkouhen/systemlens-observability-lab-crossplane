# Architecture : Hybride Fleet

Architecture de référence avec Elastic Stack `9.5.4`. Les applications,
Kubernetes et les VM utilisent OpenTelemetry avec Kafka comme tampon : les
collecteurs Kubernetes, Edge et backend comme les agents VM utilisent la
distribution Elastic EDOT `9.5.4` (ADR-014). Les agents VM restent standalone
et sont supervisés par Fleet via OpAMP, sans policy Fleet de collecte
concurrente.

## Ce qui change par rapport à systemlens-observability-lab

Trois VM au lieu de cinq : un **cluster de gestion** (hub) pilote deux clusters cibles, et tout ce
qui tourne dans les clusters est déclaré dans Git, Collecteur Edge compris.

- **Hub de gestion `tools-01`.** Argo CD, Crossplane et ses providers, cert-manager et la clé age
  tournent dans le cluster k3s du hub. Argo CD y synchronise depuis la branche `main` du dépôt
  GitHub toute la configuration de [`gitops/`](gitops/README.md), un répertoire par groupe logique,
  Secrets compris (chiffrés par SOPS avec age) : voir [`gitops/argocd`](gitops/argocd/README.md).
  Un changement est déployé une fois poussé.
- **Crossplane compose les clusters cibles.** Par provider-kubernetes (une `ClusterProviderConfig`
  par cluster), les API du lab produisent les objets de `k3s-01` et `elk-01` : services Java
  (`Application`), PostgreSQL (`PostgreSQLInstance`, CloudNativePG), MongoDB (`MongoDBInstance`,
  MongoDB Controllers for Kubernetes), Kafka métier et OTel (`KafkaCluster`, Strimzi), Elasticsearch,
  Kibana et Fleet Server (`ObservabilityStack`, ECK). Topics, comptes SCRAM et ACL Kafka, supervision
  PostgreSQL et MongoDB, ILM, pipelines, clé API, Fleet, data view, dashboards et règles Kibana sont
  configurés par les autres providers, à travers les points d'accès réseau des back-ends.
- **Opérateurs et collecteurs par Argo CD.** Les charts Helm des opérateurs (CloudNativePG, Strimzi,
  MongoDB, ECK) et les collecteurs OTel de `k3s-01`, Collecteur Edge compris, sont synchronisés par
  Argo CD directement dans leur cluster cible.
- **Ansible n'installe plus que les hôtes** : OS, k3s, agents EDOT.
- **VM Lima.** Les VM sont décrites dans `lima/` et pilotées par `scripts/vm` (création,
  provisionnement Ansible, shell, arrêt, suppression), utilisé par le `Makefile`. Les IP `192.168.33.x` sont
  portées par le réseau partagé Lima `user-v2` et joignables entre VM. Depuis le Mac, on passe par
  les redirections de port `127.0.0.1` : 6443 (API du hub), 8080 (interface Argo CD), 6444 (API de
  k3s-01), 6445 (API de elk-01), 9200, 5601 et 8220 (elk-01), 4317 et 4318 (Collecteur Edge, k3s-01).

## Cache local des téléchargements

Une reconstruction télécharge plusieurs gigaoctets (images Elastic, Kafka, PostgreSQL, MongoDB,
opérateurs, collecteurs, archive Elastic Agent, k3s et ses images, Crossplane et ses providers) à
travers le proxy TLS ; le débit est le même depuis le Mac et depuis une VM (environ 13 Mo/s). Le
répertoire `~/.cache/poc-crossplane-lab` de l'hôte est monté par Lima (virtiofs, écriture) sur
`/var/cache/lab` dans les 3 VM et survit à `make vms-destroy` :

| Contenu | Lu par | Déposé par |
|---|---|---|
| `files/` : archive Elastic Agent, script, binaire et images système de k3s | `lab-cache file` (rôles `elastic_agent`, `k3s`) | même outil, au premier téléchargement |
| `apt/` : paquets `.deb` | `lab-cache debs-restore` (rôle `common`) | `lab-cache debs-save` |
| `podman/` : image du Collecteur Edge | `lab-cache image` (rôle `otel_edge`) | même outil, après `podman pull` |
| `k3s/<vm>/` : images de chaque cluster k3s (hub : Argo CD, Crossplane, providers ; k3s-01 : opérateurs, bases, Kafka, collecteurs, applications ; elk-01 : ECK, Elastic) | rôle `k3s`, importées au premier démarrage | `make cache-save-k3s-images`, à la fin de `make deploy` |
| `terraform-plugins/`, `crossplane-packages/` | provider-terraform et Crossplane du hub (volumes `hostPath`) | les mêmes, en fonctionnement |

`lab-cache` (`ansible/roles/common/files/lab-cache`) lit le cache, sinon télécharge puis dépose le
fichier sous un nom temporaire renommé ensuite, ce qui protège les VM provisionnées en parallèle. Les
noms portent la référence exacte (URL ou image) : un cache vide ou partiel donne le même résultat,
plus lentement. `make cache-status` affiche le contenu et le montage, `make cache-clean` le vide.

## Topologie

```text
tools-01     192.168.33.60  hub k3s : Argo CD, Crossplane et providers, cert-manager, clé age
   │  Argo CD (charts Helm, collecteurs)  ·  Crossplane (provider-kubernetes, providers des back-ends)
   ├──▶ k3s-01   192.168.33.50  k3s applicatif : services Java, PostgreSQL (CloudNativePG),
   │                            MongoDB, Kafka métier et Kafka OTel (Strimzi), Collecteur Edge
   │                            (ports du nœud 4317/4318), collecteurs OTel (Kubernetes, backend,
   │                            supervision des back-ends)
   └──▶ elk-01   192.168.33.40  k3s + ECK : Elasticsearch, Kibana, Fleet Server 9.5.4 (Basic)
```

Chemin des signaux : applications et collecteurs de `k3s-01` (Service `otel-edge`), agents EDOT
des VM (`192.168.33.50:4318`) → Collecteur Edge de `k3s-01` (Deployment `otel-edge`, OTLP avec clé
Bearer) → Kafka OTel de `k3s-01` (listener interne, SCRAM, un topic par plateforme) → collecteur backend de `k3s-01` → Elasticsearch de `elk-01` (192.168.33.40:9200).
Les accès Kibana, Elasticsearch et Fleet restent directs vers `elk-01` (Services LoadBalancer
de k3s sur 9200, 5601 et 8220).

Les clusters se pilotent depuis le Mac avec les kubeconfig écrits par `make kubeconfigs` :
`.kube/tools.config` (hub, `KUBECONFIG` par défaut du `Makefile`), `.kube/k3s.config` et
`.kube/elk.config` (variables `KUBECTL_K3S` et `KUBECTL_ELK` du `Makefile`).

## Budget mémoire

Le poste a 16 Gio. Une VM vz finit par occuper sur le Mac toute la mémoire qui lui est allouée
(cache de pages invité compris) : la taille Lima est donc la vraie dépense, pas la mémoire utilisée.
Mesures du lot 8 (`free -m` dans chaque VM, lab déployé et stable) :

| VM | Allouée | Utilisée | Ce qui la remplit |
|---|---|---|---|
| `tools-01` | 4 Gio | ~2,7 Gio | serveur k3s (plafonné par `GOMEMLIMIT=1GiB`), Argo CD, Crossplane et 5 providers |
| `k3s-01` | 6 Gio | ~4,9 Gio | 3 services Java + demo-api (512 Mio max), 2 Kafka (tas 256 Mio), PostgreSQL, MongoDB, Collecteur Edge et collecteurs |
| `elk-01` | 4,5 Gio | ~3,6 Gio | Elasticsearch (tas 768 Mio, limite 1,5 Gio), Kibana (1 Gio), Fleet Server (512 Mio) |

Soit 14,5 Gio alloués, contre 22 Gio avant le lot 8 (la VM `otel-edge-01`, 1,5 Gio, est
supprimée). `k3s-01` et `elk-01` ont 4 vCPU, le hub 2. Les limites de chaque composant sont
déclarées dans Git : valeurs par défaut des API Crossplane (`gitops/crossplane/apis/*/definition.yaml`), que
chaque instance peut surcharger, valeurs Helm des opérateurs (`gitops/operators/`) et manifests des
collecteurs (`gitops/otel-pipeline/k3s-01/`).

Docker (Colima) ne sert plus au lab : GitHub construit les images applicatives et les publie sur GHCR
(voir `apps/README.md`), et `make deploy` ne fait que les attendre (`make images-wait`). Colima
n'est utile que pour les cibles optionnelles de construction locale (`make apps-build
images-import`) et pour `make otel-config-validate` (validation des configurations par l'image
EDOT). Sa VM occupe sinon jusqu'à 10 Gio sur le Mac : l'arrêter avec `colima stop` une fois ces
usages terminés (`colima start` pour la relancer).

`memory_pressure` (pourcentage libre) et `sysctl vm.swapusage` sur le Mac, `free -m` dans les VM
(`architecture/scripts/vm shell <vm> free -m`) permettent de refaire ces mesures.

## Commandes principales

`make help` affiche uniquement les parcours opérateur courants. Les cibles
techniques conservées dans le `Makefile` servent aux dépendances et aux
diagnostics ciblés ; elles restent utilisables directement lorsque cela est
nécessaire.

Pour préparer et vérifier l'environnement :

```bash
make architecture-status
make credentials-generate
make platform-status
make vm-services-status
make kubernetes-validate
make ansible-validate
make ci-run
```

Pour construire et déployer :

```bash
make apps-test               # les images sont construites par GitHub (build-images.yml)
make vms-start                # crée et provisionne les 3 VM (Ansible)
make architecture-deploy      # make deploy : hub, clusters cibles, Elastic, applications
```

Pour contrôler la chaîne d'observabilité et l'application :

```bash
make dashboards-verify
make trace-context-verify
make observability-schema-verify
make application-data-verify
make order-service-command
```

Le dashboard Kibana `Santé des flux OTel` suit les volumes de signaux, la
fraîcheur des datasets, les hostmetrics, la télémétrie des collecteurs, le lag
Kafka et les erreurs de collecte. Le déployer ou le réconcilier avec :

```bash
make otel-flow-dashboard-deploy
```

La cible utilise le secret Elasticsearch du namespace `elastic-stack` du hub. Le
dashboard est alimenté par les index `metrics-*`, `traces-*` et `logs-*` et
utilise une fenêtre par défaut de quinze minutes.

`make vm-services-status` affiche, VM par VM, l'état des unités systemd, des
conteneurs Podman et des workloads des trois clusters k3s. Le diagnostic est
en lecture seule.

`make vm-services-restart` redémarre les services des VM dans l'ordre des
dépendances (Edge, puis k3s du hub et des clusters cibles), attend les
back-ends de `k3s-01`, redémarre ensuite les Deployments applicatifs et attend
leur rollout. Cette opération perturbe temporairement la plateforme.

Les opérations de cycle de vie et de diagnostic avancé restent disponibles
depuis `make help`, notamment `make retention-deploy` et `make otel-validate`.
`make vms-destroy` est destructif et demande une validation explicite de
l'opérateur.

Documents propres à l'architecture :

- [diagramme C4 interactif](https://elkouhen.github.io/systemlens-observability-lab/c4.html#/) ;
- [provisionnement des VM `tools-01`, `k3s-01` et `elk-01`](ansible/README.md) ;
- [configuration GitOps des groupes et des clusters cibles](gitops/README.md) ;

La rétention des signaux et des logs est vérifiable avec
`make retention-verify`.
