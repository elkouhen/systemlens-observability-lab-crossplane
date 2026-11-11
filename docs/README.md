# Documentation système

Ce répertoire contient les procédures et les références communes au dépôt.
Les README des composants restent propriétaires de leur configuration et de
leurs commandes détaillées.

## Parcours recommandé

1. Lire l’[architecture](architecture.md) pour comprendre les flux de
   télémétrie et les responsabilités des VM et du cluster.
2. Consulter le [README de l’architecture](../architecture/README.md), les
   [applications](../apps/README.md) ou le
   [provisionnement](../architecture/ansible/README.md)
   avant de modifier un composant.

Le laboratoire est la troisième étape du parcours SystemLens :

1. [SystemLens](https://github.com/elkouhen/systemlens) indexe et visualise
   les preuves statiques du code.
2. [systemlens-skill](https://github.com/elkouhen/systemlens-skill) ajoute des
   explications IA et des faits complémentaires révisables.
3. Ce dépôt exécute les applications dans Kubernetes et vérifie les signaux
   réels dans la chaîne Elastic/OpenTelemetry.

Le modèle statique de l’application de démonstration se génère depuis la
racine avec `make apps-architecture-graph`. La cible produit le graphe HTML
et les exports intermédiaires sous `apps/supermarket-demo/`; elle ne déploie
aucune ressource Kubernetes. Le déploiement complet et la validation de la
télémétrie suivent les procédures de [l’architecture](architecture.md).

## Opérer l’environnement

- [Architecture](architecture.md) : topologie, flux et validations.
- [Spécification fonctionnelle](specification-fonctionnelle.md) :
  capacités attendues et critères d’acceptation.
- [Spécification technique](specification-technique.md) : composants,
  interfaces, contraintes et contrôles techniques.
- [ADR-001 : choisir le chemin de données EDOT avec Kafka](../architecture/docs/ADR-001-choix-chemin-donnees-edot.md) :
  choix du plan de données OTLP et de la gateway.
- [ADR-002 : choisir la gestion EDOT standalone avec supervision Fleet](../architecture/docs/ADR-002-edot-standalone-ou-managed-by-fleet.md) :
  choix du mode de gestion des agents EDOT.
- [ADR-008 : instrumenter les applications avec le seul agent Java OpenTelemetry](../architecture/docs/ADR-008-agent-java-opentelemetry-seul.md) :
  retrait de l'agent Java Elastic APM et point d'attachement de l'agent OTel.
- [ADR-009 : séparer les namespaces de data stream `supermarche` et `k8s`](../architecture/docs/ADR-009-namespaces-supermarche-et-k8s.md) :
  choix par l'Edge du topic Kafka suffixé de chaque ressource.
- [ADR-010 : le dataset nomme l'application, le namespace l'environnement](../architecture/docs/ADR-010-dataset-application-namespace-environnement.md) :
  noms des data streams `supermarche` et Kubernetes en `homologation`, portés
  par le nom du topic Kafka.
- [ADR-020 : la plateforme déclarée par le client, l'Edge contrôle](../architecture/docs/ADR-020-plateforme-declaree-par-le-client.md) :
  `platform.id` et `deployment.environment.name` déclarés par chaque client,
  Edge et backend sans table.
- [ADR-011 : nommer les spans HTTP client par leur chemin normalisé](../architecture/docs/ADR-011-nom-des-spans-http-client.md) :
  règles de gabarit de l'agent Java en configuration déclarative.
- [ADR-012 : plus d'ECS pour les logs](../architecture/docs/ADR-012-logs-otel-natifs-sans-ecs.md) :
  logs applicatifs exportés en OTLP par l'agent, data streams `.otel`.
- [Briques de remontée de la télémétrie](briques-remontee-telemetrie.md) :
  sources, transport, destinations et fichiers IaC associés.
- [Gestion du débit de télémétrie](gestion-du-debit-observabilite.md) :
  limitation, échantillonnage, files et quotas.

## Références techniques


## Validation reproductible

Depuis la racine du dépôt :

```bash
make ci-run
```

Le résultat attendu est un rendu Kustomize valide, une syntaxe Ansible valide
et le succès des tests Maven. Cette commande ne déploie aucune ressource.
