# Backlog : mise en œuvre d'ADR-015

Référence : [ADR-015](ADR-015-topics-par-plateforme-et-configuration-edge.md),
un topic par plateforme et environnement, configuration des plateformes
portée par l'Edge, backend générique.

Règles de travail :

- un commit par item, ou par lot quand les items partagent les mêmes
  fichiers, message décrivant l'intention ;
- les lots 0 à 4 se font sans déploiement, chaque item cite son contrôle ;
- le lot 5 déploie et détruit des topics : il attend l'accord explicite de
  l'utilisateur, item par item ;
- cocher un item uniquement quand son contrôle a réussi.

## Lot 0 : inventaire et secrets

- [x] **B01 Déclarer plateforme, environnement et Edge par VM.**
  `inventory/group_vars/{k3s,supermarket_middleware,elk,otel_edge,otel_backend}_nodes.yml` :
  `otel_platform`, `otel_environment`, `otel_edge` selon le tableau d'ADR-015,
  `kafka-local` pour `otel-backend-01`. Le rôle `elastic_agent` échoue si
  l'une des trois manque ou si `otel_edge` ne désigne ni un hôte de
  `otel_edge_nodes` ni `kafka-local`.
  Contrôle : `make ansible-validate`, puis `ansible-inventory --list` affiche
  les trois variables pour chaque VM.
- [x] **B02 Déclarer la liste des plateformes au backend.**
  `inventory/group_vars/otel_backend_nodes.yml` : `otel_platforms` avec
  `k3s`, `supermarche`, `elk` en `homologation`. Assertion dans le rôle
  `otel_backend` : toute plateforme référencée par une VM (`hostvars`) ou
  par la table des namespaces de l'Edge figure dans la liste ; noms en
  `[a-z0-9_]+`.
  Contrôle : `make ansible-validate` ; un nom hors format ou absent fait
  échouer la validation.
- [x] **B03 Une clé Edge par VM.**
  `platform/elk/scripts/generate-otel-edge-keys.sh`, `inventory/group_vars/all.yml`,
  `otel_edge_client_key_env` par groupe, listes de clés requises dans
  `architecture/Makefile` (`vms-up`, `otel-edge-vm-provision`). Clés
  `OTEL_EDGE_KEY_K3S_01`, `OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE_01`,
  `OTEL_EDGE_KEY_ELK_01`, `OTEL_EDGE_KEY_OTEL_EDGE_01` ; les clés
  `OTEL_EDGE_KEY_KUBERNETES` et `OTEL_EDGE_KEY_KUBERNETES_CLUSTER` ne
  changent pas. Le rôle `otel_edge` rend `edge.tokens` depuis les hôtes qui
  le désignent plus les deux clés Kubernetes.
  Contrôle : `make ansible-validate` ; le script régénère un fichier avec
  six clés ; `make otel-edge-vm-provision` refuse une clé absente.
- [x] **B04 Ajouter `k3s-01` au groupe `elastic_agent_nodes`.**
  `inventory/lima.yml`, `inventory/group_vars/k3s_nodes.yml`
  (`otel_edge_client_key_env`), ports sortants si le rôle `common` les
  restreint.
  Contrôle : `make ansible-validate` ; `ansible-inventory --graph` liste
  `k3s-01` sous `elastic_agent_nodes`.

## Lot 1 : backend

- [x] **B05 Créer les topics depuis `otel_platforms` dans le rôle `otel_backend`.**
  Tâche idempotente `kafka-topics.sh --create --if-not-exists` et
  `kafka-configs.sh` dans le conteneur `observability-otel-kafka`, trois
  partitions, rétention actuelle, pour `otel-{logs,metrics,traces}-<plateforme>-<env>`.
  Retirer les topics OTel du Job `otel-telemetry-topics`
  (`platform/kubernetes/base/observability/otel-kafka.yaml`), qui ne garde
  que les topics métier.
  Contrôle : `make ansible-validate`, `make kubernetes-validate` ; après
  B19, `kafka-topics.sh --list` affiche les neuf topics.
- [x] **B06 Routage backend par plateforme et environnement.**
  `roles/otel_backend/templates/otel-backend.yaml.j2` :
  `transform/data-stream-route` extrait `platform` et `namespace` de
  `^otel-(logs|metrics|traces)-(?P<platform>[a-z0-9_]+)-(?P<namespace>[a-z0-9_]+)$`,
  pose `platform.id` et `data_stream.namespace`, et sur les traces le
  namespace `<platform>_<namespace>` recopié dans `apm.route.namespace`. Plus
  aucun dataset lu dans le topic. Souscription stricte
  `^otel-(logs|metrics|traces)-[a-z0-9_]+-[a-z0-9_]+$`, plus la souscription
  transitoire `^otel-(logs|metrics|traces)(-homologation)?$` derrière une
  variable `otel_backend_legacy_topics: true`, retirée en B21.
  Contrôle : rendu du template puis `elastic-otel-collector validate` sur
  la configuration rendue.
- [x] **B07 Télémétrie interne du backend rattachée à `elk`.**
  `service.telemetry.resource` : `platform.id: elk` et
  `data_stream.namespace` = environnement de la VM.
  Contrôle : même validation qu'en B06 ; après B19, un point récent dans
  `metrics-collectortelemetry.otel-homologation` avec `platform.id: elk`
  pour `service.name: otel-backend`.
- [x] **B08 Agent EDOT de `otel-backend-01` vers les topics de sa plateforme.**
  `roles/elastic_agent/templates/elastic-agent.yml.j2` : l'exporteur
  `kafka/backend` cible `otel-<signal>-{{ otel_platform }}-{{ otel_environment }}`,
  activé par `otel_edge == 'kafka-local'` au lieu de `is_otel_backend`.
  Contrôle : rendu du template et `elastic-otel-collector validate`.

## Lot 2 : Edge et agents VM

- [x] **B09 Tables de l'Edge.**
  `inventory/group_vars/otel_edge_nodes.yml` : `otel_edge_cluster_name`,
  `otel_edge_namespace_routes` (`h0tl-supermarche-app` vers `supermarche`,
  dataset `supermarche` ; `elastic-stack` vers `k3s`, dataset `receiver`).
  Suppression de `otel_edge_application_routes` et
  `otel_edge_kubernetes_route`. `roles/otel_edge/tasks/main.yml` rend la
  table des hôtes depuis `hostvars` filtrés sur `otel_edge == inventory_hostname`
  et valide : namespace non dupliqué, plateforme présente dans
  `otel_platforms`, `dataset` égal à `receiver` ou à `[a-z0-9_.]+`.
  Contrôle : `make ansible-validate` ; une route invalide fait échouer la
  validation.
- [x] **B10 Règles de routage de l'Edge.**
  `roles/otel_edge/templates/otel-edge.yaml.j2`, macro
  `kafka_topic_statements` : règle 1 nettoyage (`data_stream.dataset`
  conservé seulement pour `collectortelemetry`), règle 2 namespaces avec
  `k8s.cluster.name`, `deployment.environment.name` et dataset hors traces,
  règle 3 hôtes par `host.name`, suppression du marqueur `otel.edge.source`.
  Nouveau processor `filter/unrouted` sur `otel.kafka.topic == nil`, placé
  avant `batch` dans les trois pipelines.
  Contrôle : `make otel-config-validate` ; relecture du rendu pour l'ordre
  des règles. Le marqueur `otel.edge.source` est conservé (note de mise en
  œuvre d'ADR-015).
- [x] **B11 Télémétrie interne de l'Edge rattachée par `host.name`.**
  `service.telemetry.resource` reçoit `host.name: {{ inventory_hostname }}`,
  ce qui la fait passer par la règle 3 vers `elk`.
  Contrôle : rendu validé ; après B20, `metrics-collectortelemetry.otel-homologation`
  reçoit `service.name: otel-edge` avec `platform.id: elk`.
- [x] **B12 Agents VM : endpoint et clé depuis `otel_edge`.**
  `roles/elastic_agent/templates/elastic-agent.yml.j2` et tâches :
  `otlphttp/edge` cible l'adresse de l'hôte `otel_edge` (`hostvars[...]`
  ou `otel_edge_ip`), la clé est `OTEL_EDGE_KEY_<HOST>` ; `resource/agent`
  pose `deployment.environment.name` depuis `otel_environment` ; `host.name`
  reste `inventory_hostname`. Installation sur `k3s-01` avec `hostmetrics`
  et `filelog/system`.
  Contrôle : rendu validé pour chaque VM ; après B20,
  `elastic-agent status` sain sur les cinq VM.

## Lot 3 : Kubernetes et validation OTLP

- [x] **B13 Collecteurs Kubernetes sans `hostmetrics` ni marqueur.**
  `platform/kubernetes/base/observability/otel-kafka.yaml` : retirer le
  receiver `hostmetrics` du DaemonSet et les processors `resource/edge-source`
  et `resource/environment` des deux collecteurs ; conserver
  `resource/k8s_cluster`. Vérifier que les dashboards `[OTel] Host` du
  nœud restent alimentés par l'agent de `k3s-01` (B12).
  Contrôle : `make kubernetes-validate` ; après B20,
  `metrics-hostmetricsreceiver.otel-homologation` reçoit `k3s-01` depuis
  `service.name: elastic-agent-otel` uniquement.
- [x] **B14 Playbook `validation/otel` compatible avec le rejet des inconnus.**
  La métrique marqueur envoyée depuis `otel-edge-01` porte `host.name` =
  `otel-edge-01` dans sa ressource, sinon l'Edge la rejette. Le README du
  playbook décrit le data stream attendu, `metrics-*.otel-homologation` avec
  `platform.id: elk`.
  Contrôle : après B20, `make otel-validation` réussit.

## Lot 4 : contrôles et documentation

- [x] **B15 Cible `make otel-routing-verify`.**
  Script `platform/elk/scripts/verify-otel-routing.sh` appelé par
  `architecture/Makefile`, lisant `otel_platforms` : sur quinze minutes,
  documents avec `platform.id` pour chaque plateforme dans `logs-*` et
  `metrics-*`, traces dans `traces-apm-supermarche_homologation` sans
  `labels.platform_id`, aucun nouveau document dans `*-default`, aucun
  champ `otel.kafka.topic`, compteur `otelcol_processor_filter_*` de l'Edge
  nul.
  Contrôle : `bash -n` et `shellcheck` si disponible ; exécution réelle
  en B21.
- [x] **B16 Requêtes et alertes sur `*-default`.**
  Inventorier dans `platform/elk/` (dashboards, `observability-policies.json`,
  data views, scripts `verify-*`) toute requête qui vise un namespace
  `default` ou dépend du marqueur Kubernetes, et la faire pointer sur
  `homologation` ou sur `platform.id`. Les dashboards Kibana actifs ne sont
  pas modifiés sans accord : versionner la correction, déployer en B21.
  Contrôle : `grep -rn -- '-default' platform/elk` ne laisse que des
  occurrences justifiées ; `make dashboards-verify` après B21. Constat du
  2026-11-03 : aucune requête versionnée ne vise un namespace `default`.
- [x] **B17 Documentation.**
  `docs/architecture.md` (flux, topics, invariants 2 à 4),
  `docs/briques-remontee-telemetrie.md`, `architecture/ansible/README.md`
  (variables par VM, onboarding d'une plateforme), `apps/ADDING_APPLICATION.md`
  (une application = une entrée de table de namespaces), README de
  `validation/otel`, modèle C4 `architecture-c4.likec4` (relations
  `Publie otel-*`).
  Contrôle : relecture, `git diff --check`, liens relatifs valides.
- [x] **B18 Statut des ADR.**
  ADR-015 passe à Accepted avec la section Vérification datée ; en-têtes
  d'ADR-005, ADR-007 et ADR-009 amendés pour renvoyer à ADR-015.
  Contrôle : relecture ; fait après B21.

## Lot 5 : migration, sur accord explicite

- [x] **B19 Étape 1, backend.** `make otel-backend-vm-provision` avec
  `otel_backend_legacy_topics: true`.
  Contrôle : neuf topics créés, `make otel-backend-vm-status` sain, lag du
  groupe `otel-backend` proche de 0, data streams applicatifs inchangés.
- [x] **B20 Étape 2, producteurs.** `make otel-edge-vm-provision`,
  `make elastic-agent-vm-provision`, `make kubernetes-observability-deploy`,
  et les clés Kubernetes via `make otel-edge-client-keys-apply`.
  Contrôle : `make otel-gateway-vm-status`, `make otel-validation`,
  les neuf topics reçoivent des messages, les anciens topics n'en reçoivent
  plus.
- [x] **B21 Étape 3, nettoyage.** Lag nul sur `otel-{logs,metrics,traces}`
  et `otel-{logs,metrics,traces}-homologation`, suppression de ces six
  topics, `otel_backend_legacy_topics: false`, nouveau
  `make otel-backend-vm-provision`, déploiement des corrections de B16.
  Contrôle : `make otel-routing-verify`, `make trace-context-verify`,
  `make observability-schema-verify`, `make dashboards-verify`,
  `make kubernetes-otel-dashboards-verify` ; test ADR-009 rejoué avec
  `data_stream.namespace` et `platform.id` à `pirate` depuis `elastic-stack`
  (arrivée en `k3s`), puis un envoi avec un `k8s.namespace.name` inconnu
  (rejeté, compteur du filtre incrémenté). Documents de test supprimés.
  Fait le 2026-11-03, sauf la suppression des six anciens topics, laissée à
  l'opérateur (voir ADR-015, vérification).

## Lot 6 : plateforme déclarée par le client (ADR-020)

- [x] **B22 Edge sans table.** `otel_platforms` déplacé dans
  `group_vars/all.yml` ; `roles/otel_edge/tasks/platforms.yml` remplace
  `routes.yml` (plateformes servies = entrées dont l'Edge est `publisher`,
  VM rattachées contrôlées) ; `transform/kafka-topic` réduit à trois
  statements par signal, topic depuis `platform.id` et
  `deployment.environment.name` ; marqueur `otel.edge.source` et
  `k8s.cluster.name` retirés de l'Edge.
  Contrôle : `make ansible-validate`, `make otel-config-validate`, garde
  vérifiée avec `-e otel_platform=inconnue`.
- [x] **B23 Déclaration par les clients.** `resource/agent` et télémétrie
  interne des agents EDOT et de l'Edge avec `platform.id` ;
  `resource/platform` des collecteurs Kubernetes ; `platform.id`,
  `deployment.environment.name` et `k8s.cluster.name` dans
  `OTEL_RESOURCE_ATTRIBUTES` des pods ; métrique de `validation/otel` avec
  `platform.id`.
  Contrôle : `make kubernetes-validate` ; après déploiement,
  `make otel-routing-verify` et `make otel-validation`.
- [x] **B24 Backend sans lecture du topic.**
  `transform/data-stream-namespace` depuis `platform.id` et
  `deployment.environment.name` ; retrait de `resource/kafka-topic`,
  `transform/data-stream-route` et de la suppression des `data_stream.*` de
  record ; Edge avec un seul `batch`, sans suppression de
  `data_stream.dataset`.
  Contrôle : `make otel-config-validate`.
- [x] **B25 Déploiement.** `make elastic-agent-vm-provision`,
  `make apps-deploy`, `make demo-api-deploy`, `make otel-edge-vm-provision`,
  `make kubernetes-observability-deploy`, `make otel-backend-vm-provision`.
  Contrôle : `make otel-routing-verify`, `make otel-validation`, compteur
  `otelcol_processor_filter_*` nul.
  Fait le 2026-11-09 ; le conflit de mapping `metrics.jvm.memory.used`
  préexistant est résolu par la purge des data streams de télémétrie, et
  `make dashboards-verify` réussit (ADR-020, vérification).

## Lot 7 : gabarits de spans HTTP client dans l'agent (ADR-011 révisé)

- [x] **B26 Configuration déclarative de l'agent Java.** `otel/agent.yaml`
  (commun aux trois services supermarché, et demo-api) remplace les
  fichiers `otel.properties` ; `OTEL_CONFIG_FILE` dans les patches ; règle
  `url_template_rules` pour `/api/reservations` ; ConfigMap hachée pour
  redémarrer les pods à chaque modification.
  Contrôle : démarrage de l'agent sans erreur dans les quatre pods, span
  `POST /api/reservations` avec `url.template`.
- [x] **B27 Retrait de `transform/http-client-span-name` de l'Edge.**
  Contrôle : `make otel-config-validate`, `make otel-routing-verify`,
  `make trace-context-verify`, `make observability-schema-verify`.
- [x] **B28 Règles de gabarit génériques.** Trois expressions régulières
  (deux identifiants, un, aucun) remplacent la règle explicite
  `/api/reservations` ; testées sur l'agent 2.28.1 avec un exporteur
  console avant déploiement.
  Contrôle : `POST /api/reservations` avec `url.template` après
  `make apps-deploy`.
