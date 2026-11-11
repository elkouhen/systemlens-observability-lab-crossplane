# ADR-003 : migrer Kubernetes de k3d vers k3s sur une VM

## Statut

Accepted

## Date

2026-09-27

## Contexte

Le cluster Kubernetes utilisé par le lab était un cluster k3d local nommé
`elastic`. Cette exécution dépend du runtime Docker de la machine opérateur et
ne fournit pas un nœud Kubernetes indépendant pour les contrôles réseau et
les validations de la chaîne d'observabilité.

Les manifests Kustomize, les VM Elastic et les services de données constituent
déjà la source de vérité du déploiement. La migration doit donc conserver ces
manifests et déplacer uniquement le plan de contrôle et les workloads
Kubernetes vers une VM dédiée.

## Décision

Le lab utilise un cluster k3s mono-nœud sur `k3s-01`, avec l'adresse privée
`192.168.33.50`. La configuration du serveur k3s est provisionnée par Ansible
et la VM est déclarée dans `lima/k3s-01.yaml` et l'inventaire `ansible/inventory/lima.yml`.

Le kubeconfig est exporté localement dans `.kube/k3s.config`. Ce fichier n'est
pas versionné. Les cibles `make` l'utilisent par défaut pour appliquer les
manifests et importer les images applicatives dans le runtime containerd de
k3s.

La cible `make k3s-migrate` démarre et provisionne la VM, exporte le kubeconfig,
valide les manifests, importe les images et réapplique la plateforme Elastic,
les collecteurs OTel et les trois services applicatifs. Le cluster k3d reste
disponible jusqu'à la validation explicite de la migration.

Le stockage Elasticsearch et les middlewares restent sur leurs VM existantes.
La migration ne transfère pas de données persistées ; elle réutilise les
endpoints et les secrets opérateur déjà prévus par le dépôt.

## Alternatives considérées

### Conserver k3d

Cette option ne répond pas au besoin d'un cluster Kubernetes porté par une VM
indépendante. Elle reste utile comme environnement de comparaison pendant la
recette et n'est donc pas supprimée automatiquement.

### Installer k3s sur une VM existante

Cette option réduirait le nombre de VM, mais mélangerait le plan de contrôle
Kubernetes avec Elasticsearch, les brokers Kafka ou le Collecteur Edge. Elle
augmenterait le risque de contention et compliquerait le diagnostic.

### Déployer un cluster k3s multi-nœuds

Cette option fournirait une meilleure tolérance aux pannes, mais elle dépasse
le besoin du lab et augmenterait les ressources et les opérations nécessaires.

## Conséquences

- le cluster dispose d'une adresse réseau privée stable et d'un kubeconfig
  indépendant du runtime Docker local ;
- les images applicatives doivent être importées dans containerd avec
  `k3s ctr`, et non dans le registre d'images Docker de k3d ;
- la VM k3s devient une dépendance supplémentaire en mémoire et en stockage ;
- la recette doit vérifier les nœuds, les pods, les services, les collecteurs
  OTel et les endpoints applicatifs avant l'arrêt de k3d ;
- la suppression de k3d reste une opération séparée et explicite.

## Références

- [`lima/k3s-01.yaml`](../lima/k3s-01.yaml)
- [`ansible/site.yml`](../ansible/site.yml)
- [`ansible/roles/k3s/tasks/main.yml`](../ansible/roles/k3s/tasks/main.yml)
- [`Makefile`](../Makefile)
