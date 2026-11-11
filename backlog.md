# Backlog : étendre la couche Crossplane

Objectif : faire gérer par Crossplane le maximum de la configuration du lab, avec le provider le plus
adapté à chaque service. État de départ : [`architecture/platform/crossplane/README.md`](architecture/platform/crossplane/README.md).

Règles de travail :

- un item n'est coché que quand son contrôle a réussi sur les VM ;
- les tâches impératives ne sont retirées d'Ansible ou du Makefile qu'une fois l'équivalent
  Crossplane vérifié.

## Recherche de providers (11 novembre 2026)

| Service | Candidat | Constat | Décision |
|---|---|---|---|
| MongoDB | `pelotech/provider-mongodb-users` | Upjet, une seule ressource `User`, dernier push en mai 2024, anciennes API sans variante namespacée | Écarté |
| MongoDB | `jasonmimick/provider-mongodb`, `svchaudharialliazn/custome-provider-MongoDB` | MongoDB Atlas uniquement, pas d'instance auto-hébergée | Écartés |
| MongoDB | `provider-terraform` + Terraform `Kaginari/mongodb` | v1.0.1 (septembre 2026), 28 étoiles, ressources `database_user`, `database_role`, `database_collection`, `database_index` | Retenu, validé par l'utilisateur (lot 2) |
| Kubernetes | `crossplane-contrib/provider-kubernetes` v1.4.1 | Actif, release d'octobre 2026 | Retenu (lot 3) |
| Helm | `crossplane-contrib/provider-helm` v1.5.0 | Actif, release d'octobre 2026. Mais rien dans le lab n'est déployé par Helm : les collecteurs Kubernetes sont des manifests bruts et `eck-stack-values.yaml` n'est plus utilisé | Pas installé (décision de l'utilisateur) |
| Elastic | `bigjbiggever/provider-upjet-elasticstack` | Voir ci-dessous | Écarté (lot 4) |

### `bigjbiggever/provider-upjet-elasticstack`

- Créé en février 2026, 5 commits, un seul contributeur, 2 étoiles, dernier commit de code le 31 mars 2026.
- Une seule release, `0.1`, de mars 2026. Le README indique « not yet ready for production ».
- 6 ressources, avec l'état annoncé par le README :
  - `ClusterSettings` et `ElasticsearchUser` : « Working - Needs Testing » ;
  - `ElasticsearchRole` : « Partially implemented - Not working » ;
  - `SnapshotLifecycle`, `SnapshotRepository`, `IndexLifecycle` : « Unknown ».
- Parmi ce que le lab utilise, seul l'ILM est couvert, et son état est inconnu. Il manque les
  component templates, les pipelines d'ingestion, les clés API, Fleet et tout Kibana.
- Non vérifié : la publication d'un package installable (`xpkg`).

## Décisions de l'utilisateur (11 novembre 2026)

1. **SLO abandonnés** : ils ne sont plus déployés, ni par Terraform ni par `provider-http`.
2. **MongoDB** : d'accord pour `provider-terraform` avec le provider Terraform `Kaginari/mongodb`.
3. **Applications** : une API `Application` (XRD + Composition), pas de simples `Object`.
4. **provider-helm** : non installé.
5. **MongoDB** (après test du provider) : d'accord pour un compte administrateur MongoDB amorcé par
   Ansible, utilisé ensuite par Crossplane, comme `otel_admin`, `observability` et `elastic`.

## Lot 0 : valider l'existant

- [x] **V01 Reconstruction complète.** `make vms-destroy vms-up deploy` sur des VM neuves, en cours
  au moment de la rédaction.
  Contrôle : la commande se termine sans erreur ; `make crossplane-status` affiche toutes les
  ressources `SYNCED=True READY=True`.
- [x] **V02 Fleet sur un Kibana neuf.** Sur les anciennes VM, le Workspace `fleet` échouait en HTTP 409
  parce que l'ancienne `kibana.yml` avait déjà créé l'hôte Fleet Server et la policy `otel-fleet`.
  Contrôle : Workspace `fleet` en `Ready` ; Fleet Server `HEALTHY` ; les 5 agents EDOT visibles dans Fleet.
  Résultat (11 novembre) : le 409 a disparu, mais le Kibana neuf refusait les versions épinglées
  (HTTP 400 « out-of-date ») ; corrigé par `force = true` dans `elastic/fleet.yaml`. Fleet liste
  5 agents `online` : les agents EDOT OpAMP de supermarket-middleware-01, otel-backend-01,
  otel-edge-01, elk-01, et Fleet Server. L'agent EDOT de `k3s-01` n'est pas inscrit dans Fleet,
  par conception du lab (`provision-fleet-vms.sh` ne traite que ces 4 VM).
- [x] **V03 Clients Kafka en SCRAM.** Edge, backend et agents EDOT publient et consomment avec les
  comptes créés par Crossplane.
  Contrôle : `make otel-kafka-acl-verify`, `make dashboards-verify`, `make otel-validate`.
- [ ] **V04 Commit initial.** Accord de l'utilisateur donné le 11 novembre (« fini tout ») : voir F04.

## Lot 1 : règles Kibana en Terraform

Les règles d'alerte quittent `provider-http` pour la ressource dédiée du provider
`elastic/elasticstack`. Les dashboards restent en `provider-http` : `elasticstack_kibana_dashboard`
impose de réécrire les panneaux ES|QL dans son propre schéma. Les SLO sont abandonnés.

- [x] **K01 Règles d'alerte.** Nouveau Workspace `kibana-alerting` : `elasticstack_kibana_alerting_rule`
  en `for_each` sur les 4 règles de `platform/elk/alerts/observability-policies.json`, passées par le
  ConfigMap `elastic-assets` (`rule_id`, `name`, `consumer`, `rule_type_id`, `interval`, `tags`,
  `params = jsonencode(...)`). Retirer les règles de `scripts/kibana-requests.py` et supprimer les
  4 `Request`. Les règles existent déjà sous les mêmes identifiants : supprimer les `Request` d'abord
  (ce qui supprime les règles), puis appliquer le Workspace.
  Contrôle : Workspace `Ready` ; `GET /api/alerting/rule/<id>` répond 200 pour les 4 ; une règle
  modifiée à la main dans Kibana revient à sa définition.
  Résultat (11 novembre) : Workspace `kibana-alerting` `Ready` ; les 4 règles répondent 200 ;
  une règle renommée et passée à 7m à la main à 09:06 est revenue à sa définition à 09:15
  (intervalle de réconciliation de provider-terraform).
- [x] **K02 Retrait des SLO et nettoyage.** `scripts/kibana-requests.py` ne génère plus que les
  2 dashboards : retirer la branche SLO et `INCLUDE_SLOS`. Le tableau `slos` reste dans
  `observability-policies.json`, que la cible `observability-policies-validate` contrôle encore, mais
  plus rien ne le déploie. Mettre à jour le README Crossplane et `make crossplane-kibana-wait`.
  Contrôle : `kibana-requests.py` génère 2 requêtes ; aucune mention de SLO déployé dans le README.
  Résultat : `kibana-requests.py` génère 2 requêtes ; le README ne cite les SLO que comme abandonnés.

## Lot 2 : MongoDB

Le compte de supervision `otel_monitor` (rôle `clusterMonitor` sur `admin`) est encore créé par
`podman exec mongosh` dans le rôle `supermarket_middleware`. MongoDB tourne sans authentification
(`mongod` sans `--auth`) et son port 27017 est ouvert vers `k3s-01`.

Constat du test (11 novembre) : le provider Terraform `Kaginari/mongodb` v1.0.1 envoie toujours des
identifiants. Sur un MongoDB sans compte, l'authentification échoue (`AuthenticationFailed`) : il ne
peut pas créer le premier utilisateur. Décision : Ansible amorce un compte administrateur, que
Crossplane utilise pour tout le reste.

- [x] **M01 Compte administrateur amorcé par Ansible.** Le rôle `supermarket_middleware` crée de façon
  idempotente un compte administrateur MongoDB (`crossplane_admin`, rôles `userAdminAnyDatabase` et
  `clusterMonitor` sur `admin`, plus si nécessaire), mot de passe dérivé de
  `.observability-credentials.env`. MongoDB reste sans `--auth` pour ne pas changer le
  comportement du lab.
  Contrôle : `db.getUser('crossplane_admin')` montre les rôles ; une connexion authentifiée avec ce
  compte réussit.
  Résultat : `getUser('crossplane_admin')` montre `userAdminAnyDatabase` et `clusterMonitor` ;
  `mongosh -u crossplane_admin` s'authentifie. Mot de passe `sha256(MONGODB_PASSWORD:crossplane_admin)`.
- [x] **M02 Accès Crossplane.** `ClusterProviderConfig` Terraform `mongodb` avec le provider
  `Kaginari/mongodb` (`~> 1.0`) pointant sur `192.168.33.10:27017`, identifiants du compte M01 déposés
  par `credentials.sh`. Vérifier que provider-terraform télécharge ce provider à travers le proxy TLS.
  Contrôle : un Workspace vide passe en `Ready`.
  Résultat : le provider `Kaginari/mongodb` est téléchargé à travers le proxy (cache
  `/tf/plugin-cache/registry.terraform.io/kaginari`). provider-terraform v1.2.0 ne passe un Workspace
  en `Ready` que s'il a au moins une ressource ou une sortie : le Workspace de contrôle, sans
  ressource, avait une seule sortie, puis a été supprimé.
- [x] **M03 Compte de supervision par Crossplane.** Workspace `mongodb-monitoring` : `mongodb_db_user`
  `otel_monitor`, base `admin`, rôle `clusterMonitor`, mot de passe lu dans un Secret déposé par
  `credentials.sh`. La tâche Ansible qui crée `otel_monitor` est retirée ; seul l'amorçage de M01
  reste dans Ansible.
  Contrôle : `db.getUser('otel_monitor')` montre le rôle ; les data streams `metrics-mongodb*` sont
  alimentés ; le compte supprimé à la main est recréé par Crossplane.
  Résultat : migration en supprimant le `otel_monitor` créé par Ansible, recréé par le Workspace ;
  `metrics-mongodbreceiver.otel-supermarche_homologation` alimenté sans redémarrer l'agent ; compte
  supprimé à la main à 09:23:46, recréé à 09:29:43 ; `make middleware-vm-provision` passe sans la tâche.

## Lot 3 : Kubernetes avec provider-kubernetes

À savoir : Crossplane tourne dans le même cluster que les workloads, et Crossplane v2
sait déjà composer des ressources Kubernetes natives dans une Composition. `provider-kubernetes`
apporte deux choses en plus : des `Object` autonomes, sans Composition, et la copie de valeurs entre
objets (`references.patchesFrom`).

- [x] **P01 Installation.** `provider-kubernetes` v1.4.1, `ClusterProviderConfig` en
  `InjectedIdentity`, ServiceAccount dédié avec les droits nécessaires.
  Contrôle : provider `Healthy` ; un `Object` de test crée un ConfigMap.
  Résultat : provider `Healthy` (ServiceAccount `provider-kubernetes`, ClusterRole
  `provider-kubernetes-objects`) ; un `Object` de test a créé puis supprimé un ConfigMap.
- [x] **P02 Secrets applicatifs.** Remplacer les `kubectl create secret` du Makefile
  (`otel-edge-client-keys` dans 3 namespaces, `postgresql-credentials`,
  `postgresql-fleet-credentials`, `elasticsearch-es-elastic-user`) par des `Object` qui copient leurs
  valeurs depuis un Secret source unique de `crossplane-system`.
  Contrôle : les Secrets existent dans leurs namespaces ; un Secret supprimé à la main est recréé ;
  les cibles `*-credentials-apply` correspondantes sont retirées.
  Résultat : 6 Secrets et 2 namespaces en `Object` (`platform/crossplane/kubernetes/secrets.yaml`),
  valeurs identiques ; `postgresql-credentials` supprimé à la main recréé dans la seconde (watch) ;
  cibles `otel-edge-client-keys-apply` et `postgresql-credentials-apply` retirées.
- [x] **P03 Manifests de la plateforme.** Les 18 objets de `platform/kubernetes/overlays/local`
  (namespace, Services et EndpointSlices vers les VM, IngressRoutes, collecteurs OTel, RBAC) deviennent
  des `Object`, générés depuis la sortie de Kustomize pour garder les manifests comme source.
  Contrôle : `kubectl apply -k` n'est plus appelé par `elk-deploy` ; les collecteurs tournent ; un
  Deployment modifié à la main est réaligné.
  Résultat : 18 `Object` `Ready` ; `elk-deploy` et les autres cibles appellent
  `crossplane-kubernetes-apply` ; collecteurs `1/1`. Un champ déclaré modifié à la main
  (`replicas`, limite mémoire) est réaligné aussitôt ; un champ ajouté par un autre gestionnaire
  (variable posée par `kubectl set env`) est conservé, comme le veut le server-side apply.
- [x] **P04 API `Application`.** Un XRD `Application` et sa Composition produisent, à partir de
  quelques paramètres (nom, image et tag, port, plateforme OTel, variables propres au service), le
  Deployment, le Service et l'instrumentation OTel d'un service. `supermarket-demo` (order,
  inventory, restock) et `demo-api` sont déclarés comme des `Application`. Les workloads produits
  gardent les noms, namespaces, labels et variables d'environnement actuels, pour que les
  vérifications du lab continuent de passer. Le `kubectl apply -k` et le `kubectl set image` de
  `make apps-deploy` et `make demo-api-deploy` disparaissent.
  Contrôle : les `Application` sont `Ready` ; `make application-data-verify`,
  `make order-service-command` et `make trace-context-verify` passent ; changer le tag d'une
  `Application` redéploie le service.
  Résultat : 4 `Application` `Ready` ; variables d'environnement identiques aux anciens manifests ;
  `application-data-verify`, `order-service-command`, `trace-context-verify` passent (traces des
  nouveaux pods) ; le tag de demo-api passé à `1.1.1-crossplane` a redéployé le pod. Écart : un
  ConfigMap d'agent par service (`<service>-otel-agent-config`) au lieu de
  `supermarket-otel-agent-config` partagé.

## Lot 5 : supprimer toute trace de Vagrant et VirtualBox (demande de l'utilisateur, 11 novembre)

Le repo ne doit plus contenir aucune mention de Vagrant ni de VirtualBox : code, configuration, docs,
ADR, commentaires et noms. Il y avait 124 occurrences dans 36 fichiers au moment de la demande
(`grep -rIi -E 'vagrant|virtualbox|vbox'`).

- [x] **N01 Adaptateur de VM.** Renommer `architecture/scripts/vagrant` en `architecture/scripts/vm`.
  Remplacer la variable `VAGRANT` du Makefile par `VM`. Remplacer les sous-commandes qui imitaient
  Vagrant par une interface propre à Lima (par exemple `vm up|provision|shell|status|stop|delete`),
  et mettre à jour tous les appelants : Makefile, `deploy-all.yml`, scripts.
  Résultat : `architecture/scripts/vm` (`up`, `provision [--playbook fleet-agent]`, `shell`,
  `ssh-config`, `state`, `status`, `stop`, `restart`, `delete`) ; variable `VM` exportée par le
  Makefile ; appelants mis à jour (Makefiles, `deploy-all.yml`, scripts, `provision-fleet-vms.sh`).
- [x] **N02 Utilisateur des VM.** Remplacer l'utilisateur `vagrant` des VM (Lima `user.name`,
  `ansible_user`, inventaire de validation) par un nom neutre, par exemple `lab`. Cela impose de
  recréer les VM, donc de le faire avant la validation finale de bout en bout.
  Résultat : utilisateur `lab` (Lima `user.name`, `ansible_user`, inventaire de validation) ;
  `scripts/vm shell k3s-01 whoami` répond `lab` sur les VM recréées.
- [x] **N03 Code, configuration et documentation.** Réécrire les commentaires, tâches Ansible
  (« variables injectées par Vagrant »), README, `AGENTS.md`, ADR et docs pour parler de Lima. Retirer
  les entrées `.vagrant` du `.gitignore`. Supprimer les journaux locaux `.vms-up.log` et
  `.full-deploy.log` à la racine du repo.
  Résultat : textes réécrits pour Lima ; `.gitignore` sans `.vagrant` ; `.vms-up.log` et
  `.full-deploy.log` supprimés.
- [x] **N04 Validation.** `grep -rIi -E 'vagrant|virtualbox|vbox'` sur le repo (hors `.git`) ne
  renvoie plus rien, en dehors de ce fichier `backlog.md`. Reconstruction complète
  (`make vms-destroy vms-up deploy`) sans erreur, puis `make crossplane-status` entièrement `Ready`.
  Résultat (11 novembre, 10:28) : le grep ne trouve plus que `backlog.md` ; reconstruction complète
  `make vms-destroy vms-up deploy` en EXIT 0 ; `make crossplane-status` : 92 ressources gérées,
  4 `OtelPlatform` et 4 `Application` `SYNCED=True READY=True`. Sur ces VM neuves passent aussi
  `otel-kafka-acl-verify`, `dashboards-verify`, `otel-validate`, `application-data-verify`,
  `order-service-command` et `trace-context-verify` ; Fleet Server `HEALTHY`, 5 agents `online` ;
  les 4 règles répondent 200 ; `otel_monitor` créé par Crossplane seul, `metrics-mongodb*` alimenté.
  Une première reconstruction avait échoué : `config/provider-configs.yaml` avait été tronqué par une
  de mes modifications ; fichier rétabli, puis seconde reconstruction complète réussie.

## Lot 6 : cache local des téléchargements (demande de l'utilisateur, 11 novembre)

Chaque reconstruction retélécharge tout à travers le proxy TLS et le réseau Lima `user-v2`. Objectif :
une reconstruction avec cache chaud ne télécharge plus rien de ce qui a déjà été récupéré une fois.
Le lab doit continuer à fonctionner avec un cache vide (premier passage) et sans perte de
fidélité : mêmes versions, mêmes images.

- [x] **C01 Inventaire et mesure.** Lister ce que la reconstruction télécharge (paquets apt, images
  Podman des VM, archive Elastic Agent, agent Jolokia, k3s et ses images, images Crossplane, providers
  et fonctions, collecteurs OTel, provider Terraform, dépendances Maven et images Docker des applications),
  avec taille et durée tirées des journaux. Mesurer le débit d'une VM Lima et celui du Mac sur un même
  fichier.
  Contrôle : tableau dans ce backlog, classé par temps gagnable.
  Résultat : mesures du 11 novembre. Débit identique depuis le Mac (13,0 à 13,4 Mo/s) et depuis elk-01
  (13,6 à 13,7 Mo/s) sur l'archive Elastic Agent de 402 Mo : le goulot est le proxy, pas `user-v2`.
  Montage virtiofs : écriture 719 Mo/s, lecture 1 960 Mo/s. Temps gagnable estimé à 13 Mo/s :

  | Élément | Volume par reconstruction | Temps gagnable |
  |---|---|---|
  | Images Podman des VM (ES 1,2 Go, Kibana 1,95 Go, Agent 1,61 Go, collecteur 892 Mo x2, Kafka 4.4.0 463 Mo, MongoDB 940 Mo, PostgreSQL 484 Mo, Kafka 3.9.2 409 Mo) | 8,8 Go (7,4 Go en cache) | ~10 min |
  | Archive Elastic Agent (402 Mo x 5 VM) | 2 Go | ~2,5 min |
  | Images de k3s-01 (21 images : système, Crossplane, providers, fonctions, collecteurs, applications) | 1,7 Go | ~2 min |
  | k3s : binaire 63 Mo, images airgap 128 Mo | 191 Mo | ~15 s |
  | Providers Terraform (elasticstack, mongodb) | 96 Mo | ~8 s |
  | Paquets apt (index toujours téléchargés) | 32 Mo par VM | quelques secondes |
  | Agent Jolokia | 0,7 Mo | négligeable |
  | Paquets Crossplane (xpkg) | 148 Ko | négligeable |
  | Dépendances Maven et images Docker des applications | sur le Mac (cache Docker et Maven) | déjà hors du cycle `vms-destroy` |
- [x] **C02 Cache sur l'hôte.** Répertoire hors du repo et hors des VM, qui survit à `make vms-destroy`
  (par exemple `~/.cache/poc-crossplane-lab`), monté dans chaque VM par Lima. Cibles `make cache-status`
  et `make cache-clean`.
  Contrôle : le montage est visible dans les 5 VM ; `cache-clean` le vide.
  Résultat : `~/.cache/poc-crossplane-lab` monté en virtiofs sur `/var/cache/lab` (`lima/base.yaml`),
  créé par `scripts/vm up`. Un montage n'est pris en compte qu'à la création d'une instance Lima.
  `make cache-status` affiche « monté » pour les 5 VM. `cache-clean` vérifié sur un répertoire factice
  (`CACHE_DIR=.../.cache/poc-crossplane-lab` : contenu supprimé, répertoire conservé ; tout autre chemin
  refusé avec « CACHE_DIR inattendu »). Le vrai cache n'a pas été vidé pour garder la mesure cache chaud.
- [x] **C03 Fichiers et paquets.** Archive Elastic Agent, agent Jolokia, binaire et script d'installation
  k3s, paquets apt : lus dans le cache s'ils y sont, sinon téléchargés puis déposés dans le cache.
  Contrôle : deuxième provisionnement sans téléchargement de ces fichiers (journaux ou compteurs réseau).
  Résultat : script `/usr/local/sbin/lab-cache` (rôle `common`), écriture atomique (fichier temporaire
  puis `mv`) et journal `/var/log/lab-cache.log` (origine `present`, `cache` ou `network`). Reconstruction
  cache chaud finale : 0 ligne `network` sur les 5 VM, `debs restored` partout, aucun fichier du cache
  réécrit (dates de modification identiques avant et après). Les index apt restent téléchargés.
- [x] **C04 Images Podman des VM.** Elasticsearch, Kibana, Elastic Agent, Kafka, PostgreSQL, MongoDB,
  collecteurs OTel, etc. : chargées depuis une archive du cache si elle existe, sinon tirées puis
  sauvegardées.
  Contrôle : deuxième provisionnement sans `podman pull` réseau.
  Résultat : `lab-cache image` charge l'archive `podman/` si elle existe, sinon tire puis sauvegarde (y
  compris une image déjà présente absente du cache). Préparation des images déplacée avant les
  redémarrages systemd qui tiraient eux-mêmes les images. Reconstruction cache chaud finale : 0 « Trying
  to pull » dans le journal de supermarket-middleware-01, otel-backend-01, otel-edge-01 et elk-01.
- [x] **C05 Images de k3s-01.** Images système de k3s, Crossplane, providers, fonctions, collecteurs et
  applications : sauvegardées dans le cache après un déploiement réussi, préchargées au démarrage de k3s
  sur une VM neuve. Le cache des providers Terraform est conservé lui aussi.
  Contrôle : deuxième déploiement sans tirage d'image réseau dans k3s.
  Résultat : `make cache-save-k3s-images` (fin de `deploy-post`) exporte chaque image dans
  `k3s/lab-*.tar` (export local, contrôle `index.json`, `manifest.json`, `oci-layout`, puis copie et
  renommage) ; le rôle `k3s` les copie dans `agent/images` avant le premier démarrage, puis les retire.
  Cache des providers Terraform (`terraform-plugins/`, `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE`)
  et des paquets Crossplane (`crossplane-packages/`, `packageCache.pvc`) montés depuis le cache.
  Reconstruction cache chaud finale : 23 imports, 0 erreur d'import, 27 événements « already present on
  machine » et aucun « Pulling » ; fichiers Terraform et Crossplane inchangés.
- [x] **C06 Mesure finale.** Reconstruction complète cache froid, puis cache chaud. Noter les deux durées
  par phase (`vms-up`, `deploy`).
  Contrôle : durées consignées ici ; la reconstruction cache chaud passe sans erreur et
  `make crossplane-status` est entièrement `Ready`.
  Résultat :

  | Reconstruction | `vms-up` | `deploy` | Total | Remarque |
  |---|---|---|---|---|
  | Cache froid | 699 s | 411 s | 1 110 s (18,5 min) | 21 images k3s sauvegardées |
  | Cache chaud n° 1 | 348 s | 387 s | 735 s | archives k3s tronquées (export direct sur virtiofs), corrigé |
  | Cache chaud n° 3 | 362 s | 363 s | 725 s | images middleware tirées par systemd, corrigé |
  | Cache chaud n° 4 | 348 s | 398 s | 746 s | archive `pause` tronquée, corrigé |
  | Cache chaud final | 421 s | 380 s | 801 s (13,4 min) | aucun téléchargement, voir C03 à C05 |

  Le passage n° 2 a échoué sur une apostrophe dans un bloc `shell` Ansible (corrigé, et
  `ansible-validate` lance désormais `--list-tasks`). Après le passage final : 92 ressources gérées,
  toutes `Ready`, 4 `Application` prêtes. Gain d'environ 5 min ; le reste est du temps de démarrage
  (Elasticsearch, Kibana, Fleet, k3s, Crossplane), pas du téléchargement. La variation de `vms-up` en
  cache chaud (348 à 421 s) n'a pas été analysée ; le passage final n'a rien téléchargé.

## Lot 7 : finitions

- [x] **F01 Scripts non exécutés.** Exécuter sur les VM `vms-restart`, `vm-services-status`,
  `vm-services-restart`, `metrics-chain-restart` et `ansible/deploy-all.yml` (ou retirer ce dernier s'il
  fait doublon avec `make deploy`, en le disant). Les cibles de bascule historiques
  (`otel-gateway-kubernetes-bascule`, `otel-backend-kubernetes-bascule`, `kubernetes-observability-deploy`) :
  exécuter si elles ont encore un sens, sinon les retirer.
  Contrôle : chaque script ou cible passe, ou son retrait est justifié ici.
  Résultat : `vm-services-status`, `metrics-chain-restart`, `vms-restart` (puis 0 ressource non prête,
  aucune unité en échec, `dashboards-verify` OK), `kubernetes-observability-deploy` et
  `otel-gateway-vm-status` passent. `vm-services-restart` échouait (`rollout restart --all` refusé par
  kubectl 1.37) : boucle sur les Deployments, puis passe. `ansible/deploy-all.yml` retiré : doublon
  divergent de `make deploy` (encore `kubectl apply -k`, sans demo-api ni provisionnement edge), avec la
  cible `ansible-deploy`. Cibles de bascule retirées (`otel-gateway-vm-provision`,
  `otel-gateway-kubernetes-remove|bascule|switch`, `otel-gateway-relocate`,
  `otel-backend-kubernetes-bascule|switch`, `otel-backend-relocate`) : la répartition actuelle des
  passerelles est la seule cible du lab.
- [x] **F02 Nettoyage des objets orphelins.** Un manifest retiré de `platform/kubernetes` ou une
  `Application` retirée doit faire disparaître l'objet correspondant (élagage par label à l'application).
  Contrôle : retrait d'un manifest de test, puis disparition de l'objet dans le cluster.
  Résultat : `scripts/prune.py` supprime les objets portant `lab.io/managed-by` absents du rendu, dans les
  namespaces du rendu (`crossplane-kubernetes-apply`, `apps-deploy`, `demo-api-deploy`). Test : ConfigMap
  `prune-test` ajoutée puis retirée de la base kustomize, `Application` `prune-test` ajoutée puis retirée ;
  après réapplication, les deux objets (et le Deployment généré) ont disparu. Fichiers de test rétablis.
- [x] **F03 Restes de test.** Supprimer l'image Docker locale `mongo:8.0`.
  Résultat : `docker rmi mongo:8.0` fait, plus aucune image `mongo` locale.
- [ ] **F04 Commit initial.** Fait par la session principale une fois les lots 6 et 7 terminés.

## Lot 8 : hub de gestion et trois clusters (décision de l'utilisateur, 11 novembre 2026)

Objectif : « faire un max avec Crossplane ». Choix validés par l'utilisateur : toutes les données
dans k3s, un cluster de gestion (hub) qui pilote, Elastic sous ECK sur elk-01 (option B).

Point de départ validé (commit 2fe8362) : reconstruction complète en 921 s, 13 Application Argo CD
Synced/Healthy, 7 contrôles de télémétrie OK.

Architecture cible :

```text
tools-01     (hub, k3s, 192.168.33.60)   Argo CD, Crossplane et providers, cert-manager, clé age
k3s-01       (applicatif, k3s)           services Java, PostgreSQL, MongoDB, Kafka métier et OTel,
                                         collecteur backend OTel, collecteurs OTel
elk-01       (observabilité, k3s + ECK)  Elasticsearch, Kibana, Fleet Server 9.5.4
otel-edge-01 (VM, Ansible)               Collecteur Edge, HAProxy
supprimées : supermarket-middleware-01, otel-backend-01
```

Contrainte : le Mac a 16 Go. Mesurer la mémoire réelle à chaque étape (`top`, `limactl list`).

- [ ] H0 Mesurer la mémoire utilisée par les 5 VM actuelles (référence).
- [ ] H1 Hub `tools-01` : VM Lima, k3s, Argo CD, Crossplane, cert-manager, clé age ; k3s-01 et
  elk-01 enregistrés comme clusters Argo CD ; provider-kubernetes (une ProviderConfig par cluster
  cible) pour composer des objets dans les clusters cibles.
- [ ] H2 Opérateurs de données dans k3s-01 (Helm par Argo CD) : CloudNativePG, Strimzi, opérateur
  MongoDB (images arm64 requises). API Crossplane du hub : PostgreSQLInstance, MongoDBInstance,
  KafkaCluster ; accès du hub et de l'Edge par NodePort sur 192.168.33.50.
- [ ] H3 Groupe supermarket : bases et Kafka métier dans k3s-01, supervision par les collecteurs OTel
  du cluster (receivers postgresql, mongodb, kafkametrics) en gardant les data streams des dashboards.
- [ ] H4 Kafka OTel et collecteur backend dans k3s-01 ; l'Edge publie par NodePort (SCRAM).
- [ ] H5 elk-01 en k3s + ECK : API ObservabilityStack (Elasticsearch, Kibana, Fleet Server), mêmes
  points d'accès 192.168.33.40:9200/5601/8220 ; configuration Terraform/HTTP actuelle conservée.
- [ ] H6 Suppression de supermarket-middleware-01 et otel-backend-01 (Lima, inventaire, rôles,
  Makefile, docs, ADR) ; reconstruction complète, 7 contrôles de télémétrie, mesure mémoire.

## Lot 4 : provider Elastic natif (écarté)

`bigjbiggever/provider-upjet-elasticstack` ne couvre pas le besoin (voir plus haut). Elasticsearch et
Fleet restent sur `provider-terraform`.

- [ ] **E01 Option, hors POC.** Générer notre propre provider Upjet depuis `elastic/elasticstack`,
  limité à la dizaine de ressources utilisées (ILM, component template, ingest pipeline, API key,
  Fleet integration, agent policy, server host, alerting rule, SLO). Gain : une ressource Crossplane
  par objet Elastic au lieu d'un `Workspace` opaque. Coût : chaîne de build Go, publication d'une
  image, maintenance à chaque version du provider Terraform.
