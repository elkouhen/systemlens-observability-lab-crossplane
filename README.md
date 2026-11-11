# lab d’observabilité Elastic

Ce dépôt fournit un environnement Kubernetes et Vagrant pour observer une
application Java avec Elastic, OpenTelemetry, Kafka, MongoDB et PostgreSQL.
L’architecture active est l’architecture « Hybride Fleet ».

## Commencer ici

Pour déployer l’environnement local :

```bash
make architecture-status
make kubernetes-validate
export POSTGRESQL_PASSWORD='...'
export MONGODB_PASSWORD='...'
export ELASTIC_PASSWORD='...'
export KIBANA_PASSWORD='...'
make vms-start
make vm-status
make architecture-deploy
```

`make vms-start` démarre les cinq VM en parallèle, puis provisionne leurs rôles
avec un seul playbook Ansible parallèle. Après le contrôle `make vm-status`,
`make architecture-deploy` déploie la plateforme Elastic, Fleet,
Kubernetes et l'application.

Les quatre variables de mot de passe doivent être fournies hors Git. Le
Makefile n'utilise plus de valeur par défaut pour ces secrets.

Optionnel, uniquement derrière un proxy TLS d'entreprise (Zscaler) : les VM
ne peuvent alors pas télécharger les images `docker.elastic.co` sans sa
racine de confiance (`x509: certificate signed by unknown authority` dans le
journal d’`observability-elasticsearch`). Dans ce cas seulement,
déposer le certificat racine PEM dans `certs/zscaler-root-ca.crt`, décrit
dans [certs/README.md](certs/README.md) : le `Makefile` l'utilise
automatiquement. `ZSCALER_CA_CERT` permet d'indiquer un autre chemin absolu.
Sans interception TLS, ne déposer aucun certificat : rien n'est installé.


Le [guide d’architecture et de déploiement](docs/architecture.md) décrit les
prérequis, l’ordre des opérations et la recette fonctionnelle.

## Périmètre

Ce dépôt possède l’environnement exécutable d’observabilité : applications,
Kubernetes, Elastic, OpenTelemetry, Kafka, bases de données et déploiement.
Il ne possède ni l’outil SystemLens ni les prompts du skill.

## Projets associés

- [SystemLens](https://github.com/elkouhen/systemlens) fournit l’indexation et
  l’exploration d’architecture.
- [systemlens-skill](https://github.com/elkouhen/systemlens-skill) fournit la
  guidance agent et les descriptions de flows.

## Parcours des trois dépôts

Les trois dépôts couvrent des responsabilités distinctes et complémentaires :

| Dépôt | Responsabilité | Résultat principal |
|---|---|---|
| `systemlens` | Indexer les preuves du code Java/Spring et visualiser le modèle persistant. | Index SQLite, flux, graphes d’appels et export HTML |
| `systemlens-skill` | Enrichir ce modèle par des descriptions IA et des audits traçables. | Rapports, descriptions de flux et manifests de faits complémentaires |
| `systemlens-observability-lab` | Fournir les applications de test, le déploiement Kubernetes complet et la chaîne d’observabilité. | Workloads déployés, télémétrie Elastic et validations d’intégration |

Le parcours recommandé est le suivant :

1. Indexer l’application avec SystemLens et exporter son graphe.
2. Utiliser `systemlens-skill` pour expliquer les flux sélectionnés ou auditer
   la complexité du modèle, sans remplacer les preuves indexées.
3. Déployer l’application dans ce laboratoire afin de vérifier les signaux
   réels, les dépendances d’exécution et la chaîne Kubernetes/Elastic.

Pour indexer et exporter l’application de démonstration depuis ce dépôt :

```bash
make apps-architecture-graph
```

Cette cible exécute `doctor`, l’indexation SystemLens, l’export des flux et
produit `apps/supermarket-demo/architecture.java.html`. Elle constitue le
contrôle d’intégration entre le produit SystemLens et la fixture Java. La
validation des dépendances de modules avec CodeQL est disponible avec :

```bash
make apps-codeql-module-graph
```

Ces commandes valident le modèle statique. Pour la validation de la plateforme,
utiliser `make ci-run` sans déploiement, puis le parcours `make vms-up` et
`make deploy` après fourniture des secrets hors Git.

## Architecture active

```text
Applications Java et pods Kubernetes
    -> EDOT Kubernetes -> Kafka -> Collector backend -> Elasticsearch -> Kibana

VM de données
    -> Elastic Agent EDOT -> Collecteur Edge -> Kafka -> Collector backend -> Elasticsearch -> Kibana
```

La plateforme conserve les namespaces Kubernetes `elastic-stack` et
`h0tl-supermarche-app`. La description complète des flux se trouve dans
[`docs/architecture.md`](docs/architecture.md).

## Parcours documentaire

- [Documentation système](docs/README.md) : index des procédures et références
  transverses.
- [Architecture](architecture/README.md) : topologie et points d’entrée de la
  plateforme active.
- [Applications](apps/README.md) : code, images et manifests des workloads.
- [Plateforme](architecture/platform/README.md) : Kubernetes, Elastic et Fleet.
- [Provisionnement des VM](architecture/ansible/README.md) : Ansible, rôles et services.

Chaque sous-système conserve les procédures détaillées dans son README local.
Ces documents sont la source de vérité pour les commandes et les fichiers du
composant concerné.

## Organisation du dépôt

```text
architecture/          # plateforme et provisionnement de l’architecture active
apps/supermarket-demo/ # code Java, Docker et tests Maven
kubernetes/            # manifests applicatifs partagés, hors plateforme Elastic
docs/                  # procédures et références transverses
scripts/               # diagnostics partagés
certs/                 # certificats locaux et prérequis TLS
```

`architecture/` est le point d’entrée de l’infrastructure active. Le dépôt
conserve les manifests applicatifs sous `kubernetes/` et les validations
transverses sous `validation/` afin de séparer le déploiement métier de la
plateforme Elastic. Les cibles du Makefile d’architecture centralisent ces
chemins et restent les seuls points d’entrée opérateur.

## Validation sans déploiement

```bash
make ci-run
```

Cette cible valide le rendu Kustomize, la syntaxe Ansible et les tests Maven.
# systemlens-observability-lab-crossplane
