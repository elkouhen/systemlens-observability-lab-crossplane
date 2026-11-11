# ADR-017 : isoler les plateformes dans le Kafka OTel par des ACL

## Statut

Accepted, 2026-11-08.

Précise [ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md)
(un topic par plateforme, le topic prouve la provenance) et
[ADR-005](ADR-005-signaux-backend-vers-kafka-local.md) (publication
kafka-local). Conserve [ADR-013](ADR-013-livraison-kafka-et-telemetrie-interne.md)
(livraison Kafka).

## Date

2026-11-08

## Contexte

Le backend mutualisé déduit la plateforme et l'environnement du nom du topic
(ADR-015). Or tous les producteurs partageaient le compte `otel_publisher`,
le broker n'appliquait aucune ACL et créait les topics à la demande. Un Edge
pouvait donc écrire dans le topic d'une autre plateforme, ou créer une
plateforme que le backend aurait indexée. Le rôle du backend lisait aussi
les tables des Edge pour contrôler le registre des plateformes, ce qui
suppose un inventaire commun.

## Décision

- Le contrat entre un Edge et le backend se limite à l'adresse du broker, un
  compte Kafka propre et les topics `otel-{logs,metrics,traces}-<plateforme>-<env>`
  des plateformes qui lui sont attribuées. Le backend recalcule le reste
  depuis le topic.
- `otel_platforms` (`inventory/group_vars/otel_backend_nodes.yml`, puis
  `group_vars/all.yml` depuis ADR-020) est le registre du backend : chaque
  plateforme déclare ses `publishers`, hôtes Edge ou hôtes dont l'agent EDOT
  publie en kafka-local.
- Un compte SASL par producteur, `otel_publisher_<hôte>`, avec les droits
  `Write` et `Describe` sur les seuls topics de ses plateformes. Le rôle
  `otel_backend` ajoute ces ACL et retire celles des autres topics du
  registre à chaque provisionnement.
- `otel_consumer` lit les topics de préfixe `otel-` avec le groupe
  `otel-backend` et décrit le cluster pour `kafkametrics`.
- `otel_admin`, seul super-utilisateur, sert au broker (inter-broker et
  contrôleur KRaft, désormais authentifié) et aux outils d'administration.
- `StandardAuthorizer` est activé, sans accès par défaut, et la création
  automatique des topics est désactivée.
- Les mots de passe des producteurs et d'`otel_admin` sont dérivés de
  `KAFKA_OTEL_PUBLISHER_PASSWORD` (SHA-256 du secret et du nom du compte).
  Ce secret racine reste sur le poste de l'opérateur ; chaque VM ne reçoit
  que son mot de passe dérivé.
- La cohérence entre les tables des Edge, les VM et le registre est vérifiée
  par `make otel-config-validate` (`roles/otel_backend/tasks/inventory-check.yml`),
  pas par le provisionnement du backend.

## Alternatives considérées

- **Un Edge par plateforme cliente** : non nécessaire pour l'isolation, que
  les ACL garantissent même pour un Edge qui sert plusieurs plateformes. À
  envisager si un client administre lui-même son Edge.
- **Un secret par producteur dans le fichier d'identifiants** : plus
  indépendant, mais chaque nouveau producteur ajoute une variable à
  transmettre aux cibles `make`. La dérivation garde un seul secret ; un
  client qui gère son Edge recevrait son mot de passe dérivé.
- **ACL préfixées** : le nom `otel-<signal>-<plateforme>-<env>` ne commence
  pas par la plateforme ; des ACL littérales, trois par plateforme, évitent
  de renommer les topics.
- **`User:ANONYMOUS` super-utilisateur sur le listener contrôleur en
  clair** : rejeté, le port 9093 est ouvert et accepterait des requêtes
  d'administration sans authentification.

## Conséquences

- Une écriture hors des topics attribués est refusée par le broker
  (`TopicAuthorizationException`) ; l'Edge la journalise et la compte dans
  `otelcol_exporter_send_failed_*`.
- Ajouter une plateforme demande de l'enregistrer avec ses publishers et de
  reprovisionner le backend avant ses producteurs.
- Le compte `otel_publisher` n'existe plus. Le secret Kubernetes
  `otel-kafka-credentials` le mentionne encore, sans consommateur.
- Changer `KAFKA_OTEL_PUBLISHER_PASSWORD` change tous les comptes dérivés :
  reprovisionner le backend, puis l'Edge et l'agent du backend.

## Vérification

`make otel-config-validate`, `make otel-backend-vm-provision`,
`make otel-edge-vm-provision`, `make elastic-agent-backend-provision`, puis :

- `make otel-kafka-acl-verify` : authorizer actif, création automatique
  désactivée, ACL de chaque producteur égales aux topics de ses plateformes,
  écritures hors registre et dans une plateforme non attribuée refusées ;
- `make otel-routing-verify` : chaque plateforme continue de recevoir ses
  signaux.
