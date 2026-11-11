# Argo CD : synchronisation GitOps depuis le hub

Argo CD tourne dans le cluster de gestion `tools-01` (namespace `argocd`). Il synchronise depuis
la branche `main` du dépôt GitHub `elkouhen/systemlens-observability-lab-crossplane` chaque groupe
de `gitops/` (voir [`../README.md`](../README.md)), puis le maintient : élagage (`prune`) des
ressources retirées du dépôt et réalignement (`selfHeal`) des modifications manuelles.

```text
GitHub (main) ──▶ Argo CD (tools-01) ──▶ Application lab (apps/)
   ├─ crossplane      gitops/crossplane      hub : Crossplane (Helm), providers, API du lab
   ├─ cert-manager    gitops/cert-manager    hub : cert-manager (Helm), émetteur autosigné
   ├─ operators       gitops/operators       k3s-01 : CloudNativePG, Strimzi, MongoDB ; elk-01 : ECK (Helm)
   ├─ otel-pipeline   gitops/otel-pipeline   hub : Kafka OTel, comptes, ACL ; k3s-01 : collecteurs
   ├─ elastic         gitops/elastic         hub : ObservabilityStack, Elasticsearch, Fleet, Kibana
   ├─ supermarket     gitops/supermarket     hub : 3 services et leurs bases (composés dans k3s-01)
   └─ demo-api        gitops/demo-api        hub : API de démonstration (composée dans k3s-01)
```

Chaque Application rend son groupe avec le kustomize intégré d'Argo CD et l'applique dans le hub ;
les Secrets SOPS du groupe (`<groupe>/secrets/`) sont rendus dans le hub par une Application
imbriquée `<groupe>-secrets` avec le plugin `ksops`. Ce qui doit exister dans un cluster cible
y arrive de deux façons :

- **Crossplane** (provider-kubernetes) compose les objets décrits par les API du lab
  (`Application`, `PostgreSQLInstance`, `MongoDBInstance`, `KafkaCluster`, `ObservabilityStack`)
  et recopie les Secrets dont les pods ont besoin (`Object`) ;
- **Argo CD** déploie directement les manifests sans logique propre au lab : les charts Helm des
  opérateurs (`operators/`) et les collecteurs OTel (`otel-pipeline/k3s-01/`, Application
  `otel-pipeline-k3s-01`), avec `destination.name` égal au nom du cluster.

**Seul ce qui est poussé sur `main` est déployé.** `make gitops-check` signale les changements
locaux non committés ou non poussés ; `make argocd-sync` fait relire le dépôt sans attendre le
cycle suivant (3 minutes).

## Installation (amorçage)

`make crossplane-apply` (appelé par `make elk-deploy`, donc par `make deploy`) enchaîne, sur le
hub (kubeconfig `.kube/tools.config`, écrit par `make kubeconfigs`) :

1. `make argocd-install` : manifeste amont épinglé (`install/kustomization.yaml`, v3.5.7) avec
   - le plugin sidecar `ksops` du repo-server (`install/repo-server.yaml`, `install/cmp-ksops.yaml`),
     sur l'image KSOPS, et la clé privée age dans le Secret `argocd/sops-age`, lue depuis
     `SOPS_AGE_KEY_FILE` (`~/.config/sops/age/keys.txt` par défaut) ;
   - le bundle CA du nœud du hub (`/etc/ssl/certs/ca-certificates.crt`, racine du proxy TLS
     d'entreprise comprise) monté dans le repo-server à la place de celui de l'image
     (`install/repo-server.yaml`) : Git et tous les dépôts Helm, y compris les téléchargements
     redirigés (archives de charts sur GitHub), sans liste d'hôtes ;
   - l'interface en HTTP derrière Traefik.
2. `make crossplane-ca-apply` : bundle CA du hub dans le ConfigMap `crossplane-system/ca-bundle`,
   lu par Crossplane pour télécharger ses paquets à travers le proxy.
3. `make clusters-register` : enregistrement des clusters cibles (voir ci-dessous).
4. `make argocd-apps-apply` : vérifie les Secrets chiffrés (`make secrets-check`), signale les
   changements non poussés, puis applique l'Application racine `root.yaml`.
5. `make crossplane-install` : attend Crossplane, ses providers et ses fonctions.

Crossplane, cert-manager et les opérateurs sont des charts Helm installés par des Application Argo
CD imbriquées : la version du chart se change dans Git. Les ressources dont la CRD n'existe pas
encore (Provider avant Crossplane, XR avant leur XRD, objet d'un cluster cible avant son
opérateur) sont reprises par le retry des Application et des ressources Crossplane.

## Clusters cibles

`make clusters-register` (`scripts/clusters-register.sh`) lit le kubeconfig administrateur de
`k3s-01` et de `elk-01` dans chaque VM, le fait pointer sur l'IP privée du nœud
(`https://192.168.33.50:6443`, `https://192.168.33.40:6443`, joignables depuis le hub) et crée dans
le hub :

| Secret | Usage |
|---|---|
| `argocd/cluster-<nom>` (label `argocd.argoproj.io/secret-type: cluster`) | destination `name: <nom>` des Application Argo CD |
| `crossplane-system/cluster-<nom>` (clé `kubeconfig`) | `ClusterProviderConfig` `<nom>` de provider-kubernetes (`crossplane/install/clusters.yaml`) |

Choix : ces identifiants sont créés à l'amorçage plutôt que versionnés avec SOPS, car k3s génère
une nouvelle autorité de certification et un nouveau certificat client à chaque installation ;
versionnés, ils imposeraient de rechiffrer et de committer après chaque reconstruction. Ils restent
hors Git, comme la clé age. Seules les `ClusterProviderConfig` qui les référencent sont dans Git.

## Clé age

La clé privée age ne quitte pas le poste et le hub. Un autre opérateur doit ajouter sa clé
publique dans `.sops.yaml` puis lancer `sops updatekeys` sur les fichiers chiffrés.

## Interface

```bash
make argocd-ui       # http://argocd.localhost:8080, utilisateur admin, mot de passe copié
make argocd-status   # état de synchronisation et de santé des Application
```

`argocd.localhost` se résout en `127.0.0.1` sans entrée `/etc/hosts` ; le port 80 de `tools-01`
(Traefik, ServiceLB) est transféré par Lima sur le port 8080 de l'hôte.

## Vérification

```bash
make argocd-status                       # toutes les Application Synced et Healthy
make argocd-wait ARGOCD_APP=supermarket
make operators-wait                      # opérateurs des clusters cibles
make crossplane-status                   # ressources gérées et instances des API du lab
```
