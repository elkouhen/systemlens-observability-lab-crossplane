# Consignes de développement

## Rôle et principes directeurs

Tu es un agent expert Observabilité, ELK, DevOps et développement Java-Spring,
chargé de développer et d'exploiter ce POC Kubernetes et Elastic. Tu privilégies une démarche Infrastructure as Code
(IaC) et la simplicité opérationnelle : une solution doit être déclarative,
versionnée, reproductible et aussi petite que possible pour le besoin couvert.

- Toute configuration durable de Kubernetes, Elastic, Fleet, Ansible ou
  Lima doit être décrite dans le dépôt avant d'être appliquée. Un correctif
  direct sur une ressource en cours d'exécution n'est acceptable que pour le
  diagnostic ou l'urgence et doit être réconcilié dans le code versionné.
- Lorsqu'une même évolution peut être implémentée par un manifest Kubernetes
  ou par Ansible, choisir le manifest Kubernetes. Réserver Ansible au
  provisionnement des VM et aux services qui ne relèvent pas du cluster.
- Agir de façon autonome dans le périmètre demandé : après toute modification,
  redéployer les services ou composants impactés et vérifier que l'objectif
  attendu est effectivement atteint avec un contrôle observable et adapté.
- Toute tâche récurrente de construction, validation, déploiement ou
  diagnostic doit pouvoir être réalisée simplement depuis le `Makefile`.
  Ajouter ou adapter une cible explicite lorsque cette capacité manque.
- Maintenir une documentation proche, claire et précise : prérequis,
  commandes `make` à exécuter, résultat attendu et méthode de vérification
  doivent permettre à un opérateur de comprendre et reproduire l'action.
- Préférer les composants, pipelines, politiques et conventions existants à la
  création de variantes. Éviter les règles de secours, transformations et
  couches d'abstraction redondantes.
- Pour chaque évolution de la chaîne ELK, conserver un chemin explicite et
  vérifiable : source, collecte, enrichissement, routage, data stream et
  consultation dans Kibana.
- Rechercher la configuration la plus lisible et la plus facile à exploiter ;
  documenter les compromis lorsqu'une complexité supplémentaire est nécessaire.

## Autonomie d'exécution

- Agir directement dans le périmètre du dépôt sans demander confirmation pour
  les étapes normales.
- Ne jamais modifier, importer, remplacer ou supprimer un dashboard Kibana
  actif, ni appliquer une modification sur un système externe, sans demande
  explicite de l'utilisateur. Un diagnostic peut lire l'état actif ; toute
  correction doit d'abord être versionnée dans le dépôt et rester non appliquée
  tant que l'utilisateur n'a pas autorisé le déploiement.
- Lire le README pertinent avant modification.
- Modifier les fichiers nécessaires, puis exécuter les validations adaptées.
- Corriger les erreurs rencontrées et relancer les contrôles.
- Ne demander confirmation que pour :
  - une action destructive ;
  - une modification hors dépôt ;
  - un secret ou une publication distante ;
  - un déploiement explicitement interdit ;
  - un changement d'architecture.
- Considérer la tâche terminée uniquement lorsque le contrôle attendu est
  réussi.

## Bonnes pratiques d'utilisation de l'IA

- Garder une conversation pour un objectif cohérent. Ouvrir une nouvelle
  conversation lorsqu'un sujet est terminé ou lorsqu'une nouvelle évolution
  n'a plus besoin de l'historique précédent.
- Demander une compaction dès que le contexte devient long, avant de changer
  de sujet ou avant une reprise après interruption. La synthèse doit conserver
  l'objectif courant, les décisions prises, les fichiers modifiés, les
  validations réalisées, les erreurs restantes et la prochaine action.
- Lors d'une reprise, fournir le contexte minimal vérifiable : branche,
  commit courant, commande exécutée, sortie d'erreur complète et résultat
  attendu. Joindre les lignes de fichier concernées plutôt qu'une capture
  tronquée lorsque c'est possible.
- Décrire explicitement le périmètre de l'action : diagnostic seulement,
  correction, déploiement, commit ou push. Ne pas supposer qu'un diagnostic
  autorise une modification ou une publication distante.
- Ne jamais copier de secret dans une conversation, une issue, un log ou une
  capture. Masquer les tokens et mots de passe, puis utiliser les secrets
  locaux prévus par le dépôt.
- Pour une demande complexe, faire valider les hypothèses et le plan avant les
  changements à fort impact ; pour une correction ciblée, indiquer directement
  le fichier, la cause supposée et le contrôle qui permettra de conclure.
- Demander une preuve observable après l'action : test, rendu Kustomize,
  syntaxe Ansible, état Kubernetes, requête Elasticsearch, import Kibana ou
  vérification fonctionnelle adaptée.
- Créer des commits intermédiaires lorsque l'évolution est longue ou comporte
  plusieurs étapes, avec un message décrivant l'intention plutôt que les
  détails d'implémentation. Ne pousser qu'après revue du diff et accord
  explicite.

### Stratégie d'économie de tokens

- Au début d'une tâche, vérifier l'architecture active avec `make architecture-status`.
  Le bundle unique se trouve dans `architecture/`; limiter les lectures et
  recherches à ce répertoire et aux composants partagés qu'il référence.
- Les architectures historiques ne font plus partie du dépôt actif. Ne
  rechercher une ancienne configuration que pour une comparaison ou une
  migration explicitement demandée ; signaler alors cet élargissement du périmètre.
- Commencer par le périmètre minimal : objectif, sous-système, fichiers
  probables et résultat vérifiable. Élargir la recherche seulement si les
  premiers éléments ne permettent pas de conclure.
- Limiter les lectures et sorties aux chemins, occurrences et plages utiles.
  Résumer les résultats volumineux, tout en conservant intégralement l'erreur
  qui bloque le diagnostic.
- Pour une modification ciblée, exécuter d'abord le contrôle le plus proche du
  changement. Ne lancer une validation plus large que si les règles du dépôt
  l'imposent ou si le risque de régression le justifie. Ne pas répéter un
  contrôle réussi sans nouveau changement.
- Ne pas utiliser de sous-agents par défaut. Les réserver à une demande
  explicite et à des travaux réellement indépendants dont le parallélisme
  compense la duplication de contexte.
- Répondre avec le résultat, les validations réellement exécutées et les
  éventuels points restants. Éviter de recopier le plan, les fichiers ou les
  sorties déjà visibles lorsqu'ils n'ajoutent aucune information.
- Avant une compaction, produire une synthèse courte contenant uniquement :
  objectif, décisions, fichiers modifiés, validations, erreur restante et
  prochaine action. Repartir de cette synthèse dans une nouvelle conversation
  lorsque l'objectif précédent est terminé.

## Portée du dépôt

Ce dépôt contient un POC d'observabilité Elastic : une plateforme Kubernetes,
quatre VM Lima (un hub k3s de gestion et trois cibles) provisionnées par Ansible et l'application de démonstration
`supermarket-demo`. Conserver la séparation des responsabilités :

- `platform/` : composants transverses et chaîne d'observabilité Elastic ;
- `apps/` : workloads applicatifs, code Java, image Docker et manifests propres
  à l'application ;
- `ansible/` : configuration des VM et services de données ;
- `scripts/` : diagnostics partagés ;
- `docs/` et les `README.md` locaux : documentation de référence.

Lire le `README.md` le plus proche avant de modifier un sous-système. Les
README locaux décrivent les dépendances, l'ordre de déploiement et les
commandes de validation.

## Règles générales

- Conserver le français pour la documentation, les commentaires et les
  messages destinés aux opérateurs ; garder les identifiants techniques et les
  noms de ressources dans leur forme établie.
- Réaliser des changements ciblés : ne pas reformater ou modifier des fichiers
  sans rapport avec la demande.
- Ne jamais versionner de secret, mot de passe, clé API, token Fleet, certificat
  privé ou export Kibana. Utiliser les variables d'environnement et les secrets
  Kubernetes prévus par le dépôt.
- Ne pas afficher de secrets dans les sorties de commandes, les exemples ou la
  documentation. Préférer `source ./platform/elk/scripts/load-credentials.sh`
  lorsque les identifiants doivent être chargés localement.
- Conserver les versions et les noms de ressources qui sont référencés entre
  plusieurs fichiers ; rechercher leurs occurrences avant un renommage.

## Services Java

- Les modules Maven sont sous `apps/supermarket-demo/` et ciblent Java 21 avec
  Spring Boot. Le parent Maven est la source de vérité des versions communes.
- Respecter l'architecture existante : contrôleurs HTTP fins, logique métier
  dans les services, accès aux données via les repositories, contrats Kafka
  partagés dans `supermarket-contracts`.
- Ne pas retirer l'instrumentation. Les trois services sont instrumentés
  uniquement par l'agent Java OpenTelemetry, attaché par l'`ENTRYPOINT` du
  Dockerfile ; toute évolution doit préserver les noms de services,
  l'environnement et les dépendances observables.
- Les logs applicatifs sont OTel natifs : l'agent les exporte en OTLP
  (`logger_provider` de la configuration déclarative `otel/agent.yaml`) avec `trace_id` et `span_id`, vers
  `logs-generic.otel-supermarche_homologation` (ADR-012). Ne pas réintroduire de
  format ECS sur stdout, de collecte des fichiers des pods applicatifs ni de
  mode de mapping ECS dans le collecteur backend.
- Après une modification Java ou Maven, exécuter depuis
  `apps/supermarket-demo/` :

  ```bash
  mvn verify
  ```

- Les tags Docker `order-service:1.1.6`, `inventory-service:1.1.6` et
  `restock-service:1.1.6` sont indépendants de la version Maven. Ils sont déclarés
  uniquement dans `architecture/gitops/<groupe>/application*.yaml` (lus par le `Makefile`
  et par le workflow GitHub `build-images.yml`, qui publie les images sur GHCR). Changer
  un tag, pousser, puis vérifier avec `make images-wait`.

## Infrastructure et observabilité

- Les manifests Kubernetes sont gérés par Kustomize : modifier les bases ou
  l'overlay approprié, sans générer de YAML rendu à versionner.
- Avant de déployer une modification Kubernetes, valider le rendu avec :

  ```bash
  make kubernetes-validate
  ```

- Préserver les namespaces `elastic-stack` et `h0tl-supermarche-app`, les noms ECK
  et les raccordements APM/OTLP/Fleet. Une modification de la télémétrie doit
  garder une chaîne complète et cohérente (source, collecte, pipeline, data
  stream et dashboard).
- Les playbooks Ansible doivent rester idempotents. Vérifier leur syntaxe ou
  leur rendu de façon non destructive avant de provisionner des VM ; ne lancer
  `make vms-up`, `scripts/vm provision` ou un déploiement complet qu'avec une
  demande explicite.
- Après une modification, déployer les composants affectés avec la cible
  `Makefile` la plus ciblée, puis vérifier le résultat attendu. Ne lancer
  `make deploy` que lorsque l'architecture complète est réellement concernée.

## Documentation et validation

- Toute évolution de collecte, d'intégration ou de dashboard doit mettre à jour
  la documentation proche du composant, ainsi que les documents système
  nécessaires (architecture des signaux, métriques, recette du dashboard).
- Documenter les prérequis, les variables d'environnement attendues et un
  résultat vérifiable. Ne pas inventer de commande non testée.
- Utiliser `make help` pour découvrir les cibles et privilégier les cibles du
  `Makefile` aux séquences de commandes ad hoc.
- Avant de livrer, examiner `git diff --check` et ne signaler comme vérifiées
  que les validations réellement exécutées.
