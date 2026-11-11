# Provisionnement Ansible des VM

Les playbooks de ce répertoire créent l'infrastructure de données partagée.
L’architecture crée cinq VM séparées : `supermarket-middleware-01` pour MongoDB, Kafka métier et PostgreSQL,
`otel-backend-01` pour le broker Kafka dédié OTel et le collecteur backend OTel, `otel-edge-01` pour HAProxy et le
Collecteur Edge (EDOT Collector) et
`elk-01` pour Elasticsearch, Kibana et Fleet Server, et `k3s-01` pour le serveur
k3s et les workloads Kubernetes.
Chaque VM reçoit un Elastic Agent en mode EDOT standalone. Il collecte les logs
et métriques locaux et les envoie en OTLP au Collecteur Edge. Exception :
`otel-backend-01` publie directement ses métriques, logs, traces et sa
télémétrie interne dans le Kafka OTel local, car cette VM ne dépend pas de
l'accès OTLP à `otel-edge-01`. Aucun signal produit par l'agent EDOT du backend
ne passe par Edge. Le Kafka OTel du backend reste le buffer des signaux
Kubernetes et VM ; le Kafka de `supermarket-middleware-01` reste réservé aux événements métier.

La cible `make fleet-opamp-enable` active en plus le monitoring Fleet OpAMP
des agents EDOT vers Fleet Server sur `elk-01`. Les agents restent standalone :
la collecte reste déclarée dans Ansible et aucune intégration Fleet concurrente
n'est activée.

La télémétrie interne des agents EDOT standalone et des collecteurs EDOT
exécutés sur les VM est exportée périodiquement par OTLP vers un receiver local,
puis routée dans le dataset `collectortelemetry`. Elle comprend les métriques
(niveau `normal`, toutes les 30 s) et les logs du Collector, sans traces
([ADR-013](../docs/ADR-013-livraison-kafka-et-telemetrie-interne.md)). Chaque composant conserve la sortie propre à son
rôle : les agents et Edge envoient leurs signaux vers Kafka, tandis que le
backend les écrit dans Elasticsearch. Fleet peut ainsi afficher la
consommation CPU et mémoire des agents dans la liste des collecteurs OpAMP et
les dashboards peuvent suivre les erreurs et la performance des pipelines.

Le collecteur backend ne commite un offset Kafka qu'après l'écriture du
message dans la file persistante de son exporteur (`message_marking.after`) :
un redémarrage peut rejouer des messages, mais n'en perd pas. Si
Elasticsearch est indisponible, la file se remplit puis le lag du groupe
`otel-backend` augmente : Kafka sert de tampon (ADR-013).

En amont, l'exporteur Kafka de l'Edge a lui aussi une file persistante
(`sending_queue` sur `file_storage`, `/var/lib/observability/otel-edge` sur
`otel-edge-01`, propriété UID 1000) : un lot accepté survit à un redémarrage
de l'Edge et à une panne de Kafka. Les réessais durent au plus 30 min ; au-delà
le lot est abandonné et compté dans `otelcol_exporter_send_failed_*`, pour
qu'un refus durable (ACL, ADR-017) ne bloque pas les autres plateformes. Seul
le lot en cours dans le processor `batch` (1 s au plus) est perdu sur arrêt
brutal. File pleine, l'Edge refuse les données et les clients OTLP réessaient.

Le receiver `hostmetrics` active explicitement `system.cpu.utilization` et
`system.memory.utilization`. Ces métriques alimentent la vue Infrastructure
Hosts/Inventory avec les champs `host.name` et `data_stream.dataset:
hostmetricsreceiver.otel`, dans le namespace de la plateforme de la VM
(`metrics-hostmetricsreceiver.otel-elk_homologation`, ADR-019).

Le rôle `common` configure chrony avec `makestep 1.0 -1` et `maxpoll 6` sur
chaque source : chrony interroge ses sources au moins toutes les 64 s et saute
l’horloge dès qu’elle dérive de plus d’une seconde. Ce réglage ne suffit pas
après une veille de l’hôte : la VM reprend avec des minutes de retard, chrony
mêle des mesures d’avant et d’après le saut, marque toutes ses sources trop
variables (`~`) et, sans source sélectionnée, ne saute jamais l’horloge
(constaté le 2026-11-07 : jusqu’à 1 024 s de retard sur les cinq VM). Le timer
`chrony-resume-check.timer` vérifie donc chaque minute qu’une source est
sélectionnée ; sinon, il exécute `chronyc reset sources` puis `chronyc burst`,
et `makestep` recale l’horloge en une à deux minutes. Les tâches chrony sont
dans `roles/common/tasks/chrony.yml` ; `make time-sync-apply` les applique
seules aux cinq VM, sans redéployer le reste. Cette
synchronisation continue est nécessaire aux fenêtres temporelles des dashboards
et au chemin OTLP → Kafka → Elasticsearch. `rtcsync` maintient également
l’horloge matérielle alignée sur l’horloge système. Vérifier les cinq VM avec
`make time-sync-verify` ; la commande attend une source NTP sélectionnée et un
état `Leap status : Normal` sur chaque nœud.

Le mode EDOT standalone est idempotent : la présence de
`/opt/Elastic/Agent/elastic-agent` et du marqueur
`/etc/observability/elastic-agent-otel.mode`, ainsi que la correspondance avec
`elastic_agent_version`, conserve l'installation après un redémarrage ou un
reprovisionnement. Une installation n'est relancée que si l'agent est absent,
que le mode EDOT est absent, que la version diffère ou qu'une réinstallation
explicite est demandée. Les VM restent en mode EDOT standalone et ne reçoivent
pas de policy Fleet de collecte ; elles peuvent être visibles dans Fleet comme
collecteurs OTel monitorés par OpAMP.
Une réinstallation doit être demandée explicitement avec la variable Ansible
`elastic_agent_reinstall=true` ; elle ne fait pas partie du chemin normal de
démarrage.

Avant toute installation de paquets, `site.yml` retire durablement la route par
défaut du réseau privé avec une surcharge Netplan et configure des
résolveurs IPv4 sur l’interface NAT. Les VM Lima utilisent Ubuntu 24.04 LTS
(modèle `template:ubuntu-24.04`, `lima/base.yaml`).
Sur `supermarket-middleware-01`, la même configuration conserve une route
persistante vers le réseau des pods k3s (`10.42.0.0/16` via `k3s-01`) afin que
les connexions Kubernetes vers PostgreSQL, MongoDB et Kafka aient un chemin
retour explicite. `k3s-01` classe également ce réseau dans la zone firewalld
`trusted` afin que le trafic des pods puisse sortir par son interface privée.
Le rôle `common` actualise les index APT juste avant l'installation afin d'éviter
les références à des versions retirées des miroirs Ubuntu.
Les valeurs par défaut (`1.1.1.1,8.8.8.8`) sont déclarées par `vm_dns_servers`
dans `inventory/group_vars/all.yml` et doivent être remplacées par les DNS de l'entreprise
si le réseau sortant les impose.

La cible `make stock-view` affiche le catalogue et le stock depuis PostgreSQL
sur `supermarket-middleware-01`.

Le receiver PostgreSQL OTel émet aussi les événements `db.server.query_sample`
et `db.server.top_query`. L'extension `pg_stat_statements` est créée dans la
base applicative et dans la base `postgres`, que le receiver utilise pour les
top queries. Le collecteur backend les indexe en mode OTel natif, comme tous
ses flux (ADR-012), afin qu'ils arrivent dans `logs-postgresqlreceiver.otel-*`
(namespace `supermarche_homologation`, ADR-019), le data stream lu par les
dashboards du package `postgresql_otel`. Contrôle :
`make postgresql-otel-dashboards-verify`.

Lors du premier provisionnement, les images Elastic sont pré-téléchargées sur
`elk-01` avant le démarrage des unités Quadlet : un téléchargement sous systemd
dépasse son délai de démarrage. Derrière un proxy TLS (`ZSCALER_CA_CERT`
défini), le certificat racine est aussi monté dans Kibana
(`NODE_EXTRA_CA_CERTS`) pour l'accès au registre des packages Fleet.

Chaque VM Lima expose SSH sur un port local fixe, de `2251` à `2255`
(`ssh.localPort` dans `lima/<vm>.yaml`), repris par `ansible_port` dans
`inventory/lima.yml`. Pour changer de plage, modifier les deux fichiers.

La cible `make vms-up` démarre les cinq VM en parallèle, puis exécute un seul
playbook Ansible sur les cinq hôtes. Les rôles restent parallèles par hôte et
les variables sensibles viennent de l’environnement. Les données Kafka sont conservées dans le volume Podman
`kafka-data`, monté sur le répertoire déclaré par `KAFKA_LOG_DIRS`.

Le broker Kafka OTel protège les échanges de logs, métriques et traces avec
SASL/PLAIN et des ACL. Chaque producteur, Edge ou agent EDOT du backend,
publie avec son compte `otel_publisher_<hôte>`, dont le mot de passe est dérivé
du secret racine `KAFKA_OTEL_PUBLISHER_PASSWORD` ; le compte `otel_consumer`
est utilisé par le backend et la collecte des métriques Kafka pour consommer
(voir « Isolation des plateformes dans Kafka »). Définir
`KAFKA_OTEL_PUBLISHER_PASSWORD` et `KAFKA_OTEL_CONSUMER_PASSWORD` dans
l'environnement avant `make vms-up`. Les mots de passe
ne sont ni versionnés ni écrits dans les manifests Kubernetes. Les topics OTel
sont créés par le rôle `otel_backend` ; le Job Kubernetes
`otel-telemetry-topics` ne crée plus que les topics métier.

La cible `make vms-restart` redémarre séquentiellement les cinq VM
(`supermarket-middleware-01`, `otel-backend-01`, `otel-edge-01`, `elk-01` et `k3s-01`) sans
reprovisionnement. Une VM arrêtée est démarrée avec `--no-provision`. Le script
affiche l’état Lima final pour permettre de vérifier que chaque VM est
`Running`.

La cible `make metrics-chain-restart` redémarre uniquement la chaîne de
transport des métriques, sans reprovisionnement : collecteur backend OTel,
Kafka OTel, collecteur Edge, puis HAProxy OTLP. Elle vérifie les endpoints de
santé des collecteurs, l’état du broker et sa disponibilité du quorum.

Après une modification de la configuration du collecteur backend, utiliser
`make elastic-agent-backend-provision` pour reprovisionner uniquement
`otel-backend-01`. La cible attend les variables d’environnement habituelles
du provisionnement et ne crée pas la VM si elle n’existe pas encore.

Les agents EDOT qui envoient leurs signaux vers Edge utilisent une clé Bearer
distincte par VM, `OTEL_EDGE_KEY_<HOST>`, et les collecteurs Kubernetes leurs
deux clés propres. Les cibles Makefile qui provisionnent l'architecture
chargent automatiquement `.observability-credentials.env` et vérifient les
identifiants avant d'exécuter Ansible. Pour lancer Ansible directement, charger
le fichier dans le shell courant avec `source ./.observability-credentials.env`.
Le collecteur Edge
conserve ces clés dans `/etc/observability/otel-edge.tokens` avec le mode
`0600`.

Pour générer et charger les clés Edge et les identifiants Kafka OTel du lab dans
le shell courant, exécuter
depuis `architecture/` :

```bash
source ./platform/elk/scripts/generate-otel-edge-keys.sh
```

La même génération peut être lancée sans conserver l'environnement du script
avec `make credentials-generate`, puis le fichier peut être chargé avec
`source ./.observability-credentials.env`.

Le script conserve les clés Edge et les mots de passe dans
`.observability-credentials.env`, ignoré par Git et protégé par le mode `0600`.
Le fichier contient `POSTGRESQL_PASSWORD`, `MONGODB_PASSWORD`,
`ELASTIC_PASSWORD`, les mots de passe Kafka OTel et les six clés Edge. Un
fichier existant est complété des clés manquantes à chaque chargement. Pour
remplacer tous les identifiants, utiliser
`OBSERVABILITY_CREDENTIALS_ROTATE=1 source ./platform/elk/scripts/generate-otel-edge-keys.sh`.

Pour supprimer les cinq VM et leurs disques locaux, exécuter la cible
destructive `make vms-destroy`. Cette opération ne supprime pas les ressources
Kubernetes ni les données persistées en dehors des VM.

Après `make deploy`, la phase `deploy-post` reprovisionne le collecteur backend
avec la clé API Elasticsearch courante et active le monitoring OpAMP des
agents VM. Cette phase peut être rejouée seule avec `make deploy-post` après
une rotation de clé ou une modification de configuration.

| VM | Collecteur | Acheminement |
| --- | --- | --- |
| `supermarket-middleware-01` | MongoDB, Kafka métier, PostgreSQL | Middlewares du scénario applicatif |
| `otel-backend-01` | Kafka OTel, backend OTel | Métriques, logs et traces locales → Kafka OTel local → Elasticsearch (OTel natif) |
| `otel-edge-01` | Collecteur Edge (Contrib) ; HAProxy | OTLP Kubernetes et VM → Kafka |
| `elk-01` | Elasticsearch, Kibana, Fleet Server | Stockage, consultation et enrôlement |
| `k3s-01` | Serveur k3s | Cluster Kubernetes et workloads du lab |

## Version du Kafka OTel

Le broker Kafka OTel d'`otel-backend-01` utilise `apache/kafka:4.4.0`, monté
en place depuis `3.9.2` sur le volume `otel-kafka-data`. Le
`metadata.version` du cluster KRaft reste à `3.9-IV0` : il n'est pas finalisé,
ce qui conserve un retour arrière possible vers `3.9.2` en restaurant l'image
dans `roles/otel_backend/templates/kafka.container.j2`. Le Kafka métier de
`supermarket-middleware-01` reste en `3.9.2`.

## Routage par plateforme

Une plateforme est un namespace Kubernetes ou un groupe de VM dans un
environnement ([ADR-015](../docs/ADR-015-topics-par-plateforme-et-configuration-edge.md)).
Chaque plateforme a trois topics `otel-{logs,metrics,traces}-<plateforme>-<environnement>`,
créés par le rôle `otel_backend` depuis `otel_platforms`
(`inventory/group_vars/all.yml`). Le dataset est celui du
receiver, ou `generic` pour les signaux OTLP des applications ; le namespace
vaut `<plateforme>_<environnement>`
([ADR-019](../docs/ADR-019-namespace-par-plateforme.md)) ; la plateforme est
aussi le champ `platform.id`.

| Plateforme | Contenu | Chemin |
| --- | --- | --- |
| `k3s` | Collecteurs `otel-kubernetes*` (namespace `elastic-stack`), VM `k3s-01` | Edge `otel-edge-01` |
| `supermarche` | Namespace `h0tl-supermarche-app`, VM `supermarket-middleware-01` | Edge `otel-edge-01` |
| `demo` | Namespace `h0tl-demo-app`, API `demo-api` (`apps/demo-api`) | Edge `otel-edge-01` |
| `elk` | VM `elk-01`, `otel-edge-01`, `otel-backend-01`, collecteurs Edge et backend | Edge pour `elk-01` et `otel-edge-01`, Kafka local pour `otel-backend-01` (ADR-005) |

### Déclaration par VM

Chaque VM déclare dans ses `group_vars` sa plateforme, son environnement et
l'Edge auquel elle envoie, ou `kafka-local` pour une publication directe
dans le Kafka OTel local :

```yaml
otel_platform: supermarche
otel_environment: homologation
otel_edge: otel-edge-01
```

Le rôle `elastic_agent` en tire l'endpoint OTLP et la clé
`OTEL_EDGE_KEY_<HOST>` de la VM (hôte en majuscules, `-` remplacé par `_`),
et refuse une VM à laquelle il manque une des trois variables ou sa clé.
`k3s-01` reçoit un agent EDOT comme les autres VM : il collecte le système et
les logs du nœud, le DaemonSet `otel-kubernetes` ne collecte plus que
`kubeletstats`.

### Plateformes servies par le collecteur Edge

L'Edge ne porte aucune table ([ADR-020](../docs/ADR-020-plateforme-declaree-par-le-client.md)).
Chaque client déclare sa plateforme et son environnement dans sa ressource,
`platform.id` et `deployment.environment.name` : les agents EDOT depuis
`otel_platform` et `otel_environment`, les collecteurs Kubernetes par leur
processor `resource/platform`, les pods applicatifs dans
`OTEL_RESOURCE_ATTRIBUTES`. L'Edge sert les plateformes du registre
`otel_platforms` (`inventory/group_vars/all.yml`) dont il est `publisher` ;
`roles/otel_edge/tasks/platforms.yml` les calcule, rend la liste des VM
rattachées (hôtes dont `otel_edge` désigne cet Edge, pour leurs clés
Bearer) et refuse une VM rattachée dont la plateforme n'est pas servie.

Le processor `transform/kafka-topic` pose `otel.kafka.topic`, lu par
`topic_from_attribute` de l'exporteur Kafka :

1. `otel.kafka.topic` reçu est supprimé, ainsi que `data_stream.dataset`,
   sauf la valeur `collectortelemetry` de la télémétrie interne des agents et
   des collecteurs (ADR-019).
2. `otel.kafka.topic` = `otel-<signal>-<platform.id>-<deployment.environment.name>`
   si ce couple est servi par l'Edge.

Une ressource sans topic est rejetée par `filter/unrouted` ; les compteurs
`otelcol_processor_filter_*` de l'Edge, lus par `make otel-routing-verify`,
rendent l'oubli visible. Le backend tire ensuite du topic `platform.id`,
`data_stream.namespace` et `deployment.environment.name`, en écrasant les
valeurs reçues.

| Ressource reçue par l'Edge | Topic | Data stream |
| --- | --- | --- |
| Log, métrique ou trace d'un pod avec `platform.id` = `supermarche` | `otel-<signal>-supermarche-homologation` | `logs-generic.otel-supermarche_homologation`, `metrics-generic.otel-supermarche_homologation`, `traces-generic.otel-supermarche_homologation` |
| Métrique des collecteurs Kubernetes (`platform.id` = `k3s`) | `otel-metrics-k3s-homologation` | `metrics-<receiver>.otel-k3s_homologation` |
| Signal d'une VM (`platform.id` = `elk`) | `otel-<signal>-elk-homologation` | `<type>-<receiver>.otel-elk_homologation` |
| Télémétrie interne de l'Edge (`platform.id` = `elk`) | `otel-<signal>-elk-homologation` | `metrics-collectortelemetry.otel-elk_homologation` |
| Ressource sans plateforme, ou plateforme non servie par cet Edge | aucun | rejetée |

### Backend générique

Le backend ne porte aucune table. Il souscrit à
`^otel-(logs|metrics|traces)-[a-z0-9_]+-[a-z0-9_]+$` et pose le data stream
depuis les attributs déclarés par le client et contrôlés par l'Edge
([ADR-020](../docs/ADR-020-plateforme-declaree-par-le-client.md)) :

| Signal | Posé depuis `platform.id` et `deployment.environment.name` |
| --- | --- |
| Logs, métriques et traces | `data_stream.namespace` = `<plateforme>_<env>`, `deployment.environment` = `<env>` (cible de l'alias `service.environment` des templates OTel d'Elasticsearch, filtre de l'UI APM) ; dataset dérivé du receiver par l'exporteur, ou `generic` pour l'OTLP des applications |

Les data streams sont donc nommés `<type>-<dataset>.otel-<plateforme>_<env>`
([ADR-019](../docs/ADR-019-namespace-par-plateforme.md)) : le dataset reste
celui que sélectionnent les vues intégrées de Kibana (Infrastructure,
dashboards Fleet, APM), et chaque plateforme a ses propres data streams,
séparables par motif d'index (`*-*.otel-supermarche_*`). Le nom ne répète
pas la plateforme : `logs-generic.otel-supermarche_homologation`.

Chemin : producteur → topic du Kafka OTel → receiver `kafka/otlp`
(souscription par regex) → `transform/data-stream-namespace` (namespace
depuis les attributs, suppression de `otel.kafka.topic`) → exporteur
Elasticsearch. Tous les signaux sont en mode de mapping OTel : l'exporteur
ajoute `.otel` au dataset
([ADR-012](../docs/ADR-012-logs-otel-natifs-sans-ecs.md),
[ADR-018](../docs/ADR-018-traces-otel-natives-sans-apm-server.md)).

Les traces passent par le processeur `elasticapm` (classification
transaction/span, résultat, dépendances). Le connecteur `elasticapm` en tire
les métriques agrégées lues par l'UI APM :
`metrics-{transaction,service_transaction,service_destination,service_summary}.<intervalle>.otel-<plateforme>_<env>`.
Les métriques de l'agent Java (runtime JVM, HTTP) suivent la règle commune
et arrivent dans `metrics-<dataset>.otel-<plateforme>_<env>`.

La télémétrie interne du collecteur backend ne passe pas par Kafka : sa
ressource déclare `platform.id` et `deployment.environment.name` de la VM
et suit le même processor. L'agent
EDOT de `otel-backend-01` publie directement dans les topics de sa plateforme
(`otel_edge: kafka-local`).

### Ajouter une plateforme

1. Ajouter le couple à `otel_platforms` dans
   `inventory/group_vars/all.yml`, avec ses `publishers` :
   l'Edge qui la sert, ou l'hôte dont l'agent publie en `kafka-local`.
2. Faire déclarer la plateforme par ses clients : les trois variables
   `otel_*` pour des VM, `platform.id` et `deployment.environment.name` dans
   l’Application Crossplane d’une application Kubernetes (`spec.otel.platform`).
3. `make otel-config-validate` rend et valide les configurations, et refuse
   une VM dont la plateforme est absente du registre ou de ses `publishers`.
4. `make otel-backend-vm-provision` crée les topics, les comptes et les ACL,
   puis `make otel-edge-vm-provision` applique la liste des plateformes
   servies et le provisionnement des agents leur déclaration.
5. `make otel-kafka-acl-verify` contrôle l'isolation.

### Isolation des plateformes dans Kafka

Chaque producteur a son compte `otel_publisher_<hôte>` et ne peut écrire que
dans les topics des plateformes qui lui sont attribuées
([ADR-017](../docs/ADR-017-isolation-kafka-des-plateformes.md)). Le broker
applique les ACL (`StandardAuthorizer`), ne crée aucun topic à la demande et
authentifie tous ses listeners. `otel_admin`, seul super-utilisateur, sert au
broker et aux outils d'administration (`otel-kafka-client.properties`).

| Compte | Droits |
| --- | --- |
| `otel_publisher_otel_edge_01` | Écriture sur les topics `k3s`, `supermarche`, `elk` et `demo` |
| `otel_publisher_otel_backend_01` | Écriture sur les topics `elk` (agent EDOT kafka-local) |
| `otel_consumer` | Lecture des topics `otel-*`, groupe `otel-backend`, description du cluster |
| `otel_admin` | Super-utilisateur |

Les mots de passe des producteurs et d'`otel_admin` sont dérivés de
`KAFKA_OTEL_PUBLISHER_PASSWORD`, qui reste sur le poste de l'opérateur.

```bash
source ./platform/elk/scripts/load-credentials.sh
make otel-kafka-acl-verify
```

Résultat attendu : une ligne par producteur indiquant ses topics autorisés,
puis `refusé` pour chaque tentative d'écriture dans un topic hors registre ou
d'une plateforme qui ne lui est pas attribuée. Aucun message n'est écrit.

Vérification après publication :

```bash
scripts/vm shell otel-backend-01 'sudo podman exec -e KAFKA_OPTS= observability-otel-kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --command-config /opt/kafka/config/otel-kafka-client.properties --describe --group otel-backend'
```

Le topic doit apparaître avec un retard nul, puis
`GET _data_stream/*-<namespace>` dans Kibana Dev Tools doit lister les data
streams correspondants.

## Ordre de lecture

1. `inventory/lima.yml` : hôtes ciblés, connexion SSH et capacités propres à chaque nœud ; les variables communes sont dans `inventory/group_vars/all.yml`.
2. `site.yml` : orchestration des rôles idempotents par groupes d’inventaire.
3. `roles/` : responsabilités séparées par type de VM et composants communs.
4. `roles/*/templates/` : unités Podman Quadlet et configurations propres à chaque rôle.
5. `status.yml` : diagnostic détaillé des services sur les VM.
6. `make vms-up` prépare les VM et installe les agents EDOT. Après
  l'initialisation d'Elastic, `make deploy` déploie le stack et les applications.

## Rôles

Le playbook `site.yml` applique les rôles dans cet ordre, en utilisant les groupes de
`inventory/lima.yml` comme structure de déploiement :

1. `common` : prérequis système, réseau, pare-feu, répertoires et
   résolution des noms des VM ;
2. `elk` sur `elk_nodes` : Elasticsearch, Kibana et Fleet Server ;
3. `otel_backend` sur `otel_backend_nodes` : Kafka OTel et backend OTel ;
4. `otel_edge` sur `otel_edge_nodes` : collecteur Edge et HAProxy ;
5. `lab` sur `supermarket_middleware_nodes` : MongoDB, Kafka métier et PostgreSQL ;
6. `k3s` sur `k3s_nodes` : serveur Kubernetes ;
7. `elastic_agent` sur `elastic_agent_nodes` : téléchargement et configuration EDOT,
   après le démarrage des services dont les agents dépendent.

Les ports pare-feu, la clé d’accès Edge et les besoins spécifiques du middleware
sont également déclarés par hôte dans l’inventaire. Les rôles utilisent les
groupes Ansible comme source de vérité pour sélectionner le comportement propre
à chaque VM ; les conditions restantes portent sur l’état observé de la machine
et l’idempotence.

`site.yml` est l'unique point d'entrée du provisionnement général. Chaque rôle
possède ses propres templates afin que la tâche et la configuration déployée
restent au même endroit.

Le playbook `fleet-agent.yml` est le point d'entrée du monitoring OpAMP. Il
réapplique la configuration EDOT avec un jeton fourni temporairement par la
cible `make fleet-opamp-enable`, sans écrire ce jeton dans le dépôt.

Le script de monitoring réutilise un jeton OpAMP stable par VM ; il ne crée
donc pas une nouvelle clé lors d'un second lancement. L'identifiant OpAMP est
persisté sur la VM pour éviter les doublons dans Fleet.

Le téléchargement de l'Elastic Agent utilise un délai de 120 secondes et est
réessayé cinq fois, avec 15 secondes entre les tentatives. Ces valeurs peuvent
être adaptées ponctuellement avec `-e` si le réseau est particulièrement lent,
par exemple `-e elastic_agent_download_retries=8 elastic_agent_download_delay=30`.

Le rôle `elk` attend l'allocation des index primaires Elasticsearch avant de
réinitialiser le token de service Kibana. Une réponse 200 sur `GET /` ne suffit
pas toujours lors du premier démarrage : l'API des tokens écrit dans l'index
`.security`, qui peut encore être indisponible et répondre 503. La suppression
du token réessaie également les réponses 503 transitoires. Voir la
[documentation Elastic sur les comptes de service](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/service-accounts)
pour le stockage des tokens et la [documentation de l'API de santé du cluster](https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-cluster-health)
pour le mécanisme d'attente.

Exécuter les playbooks depuis `architecture/`, avec l'inventaire `ansible/inventory/lima.yml`.

Pour démarrer et provisionner les VM, utiliser :

```bash
make vms-up
make vm-status
```

Pour préparer le cluster k3s local, utiliser :

```bash
source ./platform/elk/scripts/load-credentials.sh
make k3s-vm-up
make k3s-kubeconfig
```

La première cible crée et provisionne `k3s-01`. La seconde exporte son
kubeconfig dans `.kube/k3s.config`. Le déploiement Elastic, OTel et applicatif
reste piloté par les cibles de déploiement dédiées.

L'installation de k3s utilise le script de la release épinglée sur GitHub. Ce
chemin évite la dépendance à `get.k3s.io` lorsque son service de distribution
est indisponible. La version reste déclarée par `k3s_version` dans
`inventory/group_vars/all.yml`.

Après vérification des services, déployer le reste de l'architecture avec :

```bash
make deploy
```

L'ordre opérationnel est volontairement séquentiel : plateforme Elastic sur
`elk-01`, backend OTel, Edge OTel, middleware du scénario, serveur k3s, puis
collecteurs Kubernetes et applications. Les namespaces et secrets Kubernetes
strictement nécessaires sont préparés en amont ; l'overlay Kubernetes complet
n'est appliqué qu'après le backend et Edge.

Lorsque `make deploy` réutilise une VM ELK déjà provisionnée, le mot de passe
Elasticsearch persistant sur `elk-01` est utilisé comme source de vérité pour
éviter un `401 Unauthorized` dû à un secret local différent. Le mot de passe
n'est jamais affiché ni versionné.

Les mots de passe restent dans `ELASTIC_PASSWORD`, `POSTGRESQL_PASSWORD` et
`MONGODB_PASSWORD` hors du dépôt. Si `MONGODB_PASSWORD` n'est pas défini, le
lab réutilise la valeur de `POSTGRESQL_PASSWORD`. Le déploiement complet passe par
`make vms-up` puis `make deploy`.

## Documentation externe

- [Guide des playbooks Ansible](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks.html)
- [Inventaires Ansible](https://docs.ansible.com/projects/ansible/latest/inventory_guide/intro_inventory.html)
- [Templates Jinja](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_templating.html)

## Rétention des VM

Le rôle `retention`, inclus dans `site.yml`, configure journald et logrotate,
puis active le nettoyage horaire des archives de plus de 24 h. Le playbook
`retention.yml` applique uniquement ces règles et la configuration Kafka ;
il redémarre le broker si son Quadlet change et réconcilie les topics existants.
Utiliser `make retention-deploy` et `make retention-verify` depuis la racine.
Les durées, plafonds, prérequis et limites sont déclarés dans les fichiers de
configuration de rétention et vérifiables avec `make retention-verify`.
