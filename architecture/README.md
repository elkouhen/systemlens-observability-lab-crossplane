# Architecture : Hybride Fleet

Architecture de référence avec Elastic Stack `9.5.4`. Les applications,
Kubernetes et les VM utilisent OpenTelemetry avec Kafka comme tampon : les
collecteurs Kubernetes, Edge et backend comme les agents VM utilisent la
distribution Elastic EDOT `9.5.4` (ADR-014). Le
cluster Kubernetes de référence est k3s sur `k3s-01` ; k3d reste disponible
uniquement pour la comparaison pendant la migration.
Les agents VM restent standalone et sont supervisés par Fleet via OpAMP, sans
policy Fleet de collecte concurrente.

## Ce qui change par rapport à systemlens-observability-lab

Même topologie (5 VM, mêmes noms, mêmes IP `192.168.33.x`, mêmes rôles), avec trois différences :

- **Configuration des back-ends par Crossplane.** Topics, comptes SCRAM et ACL Kafka, supervision
  PostgreSQL et MongoDB, ILM, pipelines, clé API, Fleet, data view, dashboards et règles Kibana sont
  déclarés dans [`gitops/`](gitops/README.md), un répertoire par groupe logique, et réconciliés en continu depuis
  `k3s-01`, comme les objets Kubernetes : Secrets, manifests de la plateforme et services applicatifs
  (API `Application`). Ansible n'installe plus que les hôtes.
- **GitOps par Argo CD.** Argo CD, dans `k3s-01`, synchronise toute cette configuration depuis la
  branche `main` du dépôt GitHub, Secrets compris (chiffrés par SOPS avec age) : voir
  [`gitops/argocd`](gitops/argocd/README.md). Un changement est déployé une fois poussé.
- **VM Lima.** Les VM sont décrites dans `lima/` et pilotées par `scripts/vm` (création,
  provisionnement Ansible, shell, arrêt, suppression), utilisé par le `Makefile`. Les IP `192.168.33.x` sont
  portées par le réseau partagé Lima `user-v2` et joignables entre VM. Depuis le Mac, on passe par
  les redirections de port `127.0.0.1` : 6443 (k3s), 9200, 5601 et 8220 (elk-01), 4317 et 4318
  (otel-edge-01).

## Cache local des téléchargements

Une reconstruction télécharge plusieurs gigaoctets (images Elastic, Kafka, PostgreSQL, MongoDB,
collecteurs, archive Elastic Agent, k3s et ses images, Crossplane et ses providers) à travers le proxy
TLS ; le débit est le même depuis le Mac et depuis une VM (environ 13 Mo/s). Le répertoire
`~/.cache/poc-crossplane-lab` de l'hôte est monté par Lima (virtiofs, écriture) sur `/var/cache/lab`
dans les 5 VM et survit à `make vms-destroy` :

| Contenu | Lu par | Déposé par |
|---|---|---|
| `files/` : archive Elastic Agent, agent Jolokia, script, binaire et images système de k3s | `lab-cache file` (rôles `elastic_agent`, `otel_backend`, `k3s`) | même outil, au premier téléchargement |
| `apt/` : paquets `.deb` | `lab-cache debs-restore` (rôle `common`) | `lab-cache debs-save` |
| `podman/` : images des services des VM | `lab-cache image` (rôles `elk`, `otel_backend`, `otel_edge`, `supermarket_middleware`) | même outil, après `podman pull` |
| `k3s/` : images de `k3s-01` (Crossplane, providers, fonctions, collecteurs, applications) | rôle `k3s`, importées au premier démarrage | `make cache-save-k3s-images`, à la fin de `make deploy` |
| `terraform-plugins/`, `crossplane-packages/` | provider-terraform et Crossplane (volumes `hostPath`) | les mêmes, en fonctionnement |

`lab-cache` (`ansible/roles/common/files/lab-cache`) lit le cache, sinon télécharge puis dépose le
fichier sous un nom temporaire renommé ensuite, ce qui protège les VM provisionnées en parallèle. Les
noms portent la référence exacte (URL ou image) : un cache vide ou partiel donne le même résultat,
plus lentement. `make cache-status` affiche le contenu et le montage, `make cache-clean` le vide.

## Topologie VM

```text
Kubernetes / opérateur
          |
          v
      otel-edge-01  -- OTLP
          |
          v
      otel-backend-01  -- Kafka OTel + backend OTel
          |
          v
      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      supermarket-middleware-01  -- Kafka métier + MongoDB + PostgreSQL

      otel-backend-01  -- Kafka OTel + exporteur backend --> elk-01
                                                  Elasticsearch + Kibana + Fleet Server
```

`otel-edge-01` est le point d’entrée OTLP exposé. Les accès Kibana,
Elasticsearch, Fleet et APM sont directs vers `elk-01`. `otel-backend-01` héberge
le Kafka dédié OTel et le Collector backend, `supermarket-middleware-01` héberge les middlewares du
scénario et son Kafka métier, et `elk-01` porte le stockage et la consultation
Elastic.

Le code Java et les images sont partagés avec la plateforme. Le déploiement et
la recette sont décrits dans le README Ansible et les cibles du `Makefile`.
Le cluster k3s de référence se prépare avec `make k3s-vm-up`, puis son
kubeconfig local peut être exporté avec `make k3s-kubeconfig`.

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
make apps-build
make apps-test
make vms-start
make architecture-deploy
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

La cible utilise le secret Elasticsearch du namespace `elastic-stack`. Le
dashboard est alimenté par les index `metrics-*`, `traces-*` et `logs-*` et
utilise une fenêtre par défaut de quinze minutes.

`make vm-services-status` affiche, VM par VM, l'état des unités systemd, des
conteneurs Podman et des workloads Kubernetes présents sur `k3s-01`. Le
diagnostic est en lecture seule.

`make vm-services-restart` redémarre les services des VM dans l'ordre des
dépendances, redémarre ensuite les Deployments applicatifs Kubernetes et
attend leur rollout. Cette opération perturbe temporairement la plateforme.

Les opérations de cycle de vie et de diagnostic avancé restent disponibles
depuis `make help`, notamment `make retention-deploy` et `make otel-validate`.
`make vms-destroy` est destructif et demande une validation explicite de
l'opérateur.

Documents propres à l'architecture :

- [diagramme C4 interactif](https://elkouhen.github.io/systemlens-observability-lab/c4.html#/) ;
- [provisionnement des VM `supermarket-middleware-01`, `otel-backend-01`, `otel-edge-01` et `elk-01`](ansible/README.md) ;

La rétention des signaux et des logs est vérifiable avec
`make retention-verify`.
