# Argo CD : synchronisation GitOps

Argo CD tourne dans `k3s-01` (namespace `argocd`). Il synchronise depuis la branche `main` du
dépôt GitHub `elkouhen/systemlens-observability-lab-crossplane` chaque groupe de `gitops/`
(voir [`../README.md`](../README.md)), puis le maintient : élagage (`prune`) des ressources
retirées du dépôt et réalignement (`selfHeal`) des modifications manuelles.

```text
GitHub (main) ──▶ Argo CD ──▶ Application lab (apps/)
                               ├─ crossplane      gitops/crossplane      API Application et OtelPlatform
                               ├─ otel-pipeline   gitops/otel-pipeline   Kafka OTel, Service Edge, collecteurs
                               ├─ elastic         gitops/elastic         accès à elk-01, Elasticsearch, Fleet, Kibana
                               ├─ supermarket     gitops/supermarket     3 services et leurs bases
                               └─ demo-api        gitops/demo-api        API de démonstration
```

Chaque Application rend son groupe avec le plugin `ksops` (`kustomize build` et générateur KSOPS
des Secrets SOPS du groupe).

**Seul ce qui est poussé sur `main` est déployé.** `make gitops-check` signale les changements
locaux non committés ou non poussés ; `make argocd-sync` fait relire le dépôt sans attendre le
cycle suivant (3 minutes).

## Installation (amorçage)

`make crossplane-apply` (appelé par `make elk-deploy`, donc par `make deploy`) enchaîne :

1. `make argocd-install` : manifeste amont épinglé (`install/kustomization.yaml`, v3.5.7) avec
   - le plugin sidecar `ksops` du repo-server (`install/repo-server.yaml`, `install/cmp-ksops.yaml`),
     sur l'image KSOPS, et la clé privée age dans le Secret `argocd/sops-age`, lue depuis
     `SOPS_AGE_KEY_FILE` (`~/.config/sops/age/keys.txt` par défaut) ;
   - le bundle CA de `k3s-01` dans `argocd-tls-certs-cm` pour `github.com` (proxy TLS d'entreprise) ;
   - l'interface en HTTP derrière Traefik.
2. `make argocd-apps-apply` : vérifie les Secrets chiffrés (`make secrets-check`), signale les
   changements non poussés, puis applique l'Application racine `root.yaml`.

Crossplane lui-même (Helm, paquets, runtime : `make crossplane-install`) reste installé par make :
les groupes en dépendent. Les ressources dont la CRD n'existe pas encore (XRD en cours
d'établissement) sont reprises par le retry des Application.

## Clé age

La clé privée age ne quitte pas le poste et le cluster. Un autre opérateur doit ajouter sa clé
publique dans `.sops.yaml` puis lancer `sops updatekeys` sur les fichiers chiffrés.

## Interface

```bash
make argocd-ui       # http://argocd.localhost:8080, utilisateur admin, mot de passe copié
make argocd-status   # état de synchronisation et de santé des Application
```

`argocd.localhost` se résout en `127.0.0.1` sans entrée `/etc/hosts` ; le port 80 de `k3s-01` est
transféré par Lima sur le port 8080 de l'hôte.

## Vérification

```bash
make argocd-status                       # toutes les Application Synced et Healthy
make argocd-wait ARGOCD_APP=supermarket
make crossplane-status                   # ressources gérées Ready
```
