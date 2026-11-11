# Supermarché en ligne — démonstration observabilité

Ce lab simule le système d'information d'un supermarché avec trois
microservices Spring Boot : `order-service` gère la prise de commande,
`inventory-service` gère le stock du catalogue et `restock-service` orchestre
le réassort asynchrone. Le Dockerfile produit une image pour chacun.

## Scénario métier

- **`order-service`** expose `POST /api/orders` (commande passée en caisse :
  produit + quantité) et appelle `inventory-service` de façon synchrone via
  REST pour réserver le stock. Il publie aussi, toutes les minutes, une
  commande aléatoire du catalogue sur Kafka, pour simuler les commandes
  passées en ligne et traitées en tâche de fond.
- **`inventory-service`** consomme ces commandes (Kafka pour le flux en ligne,
  REST pour la caisse), vérifie le stock du produit dans son catalogue
  PostgreSQL, le décrémente, puis journalise la commande dans MongoDB
  (`order_fulfillments`) et dans le registre PostgreSQL (`stock_movements`).
  Si le stock est insuffisant, une rupture de stock (HTTP 409) est renvoyée.
- **`restock-service`** consomme `supermarket.stock.depleted` publié par
  `inventory-service` après une réservation qui épuise le stock. Il publie une
  demande de 500 unités sur `supermarket.stock.restock-requested`, consommée
  par `inventory-service`, seul propriétaire du catalogue PostgreSQL.
- Pour les commandes en ligne, `restock-service` consomme aussi
  `supermarket.order.placed` avec un groupe Kafka indépendant afin d'observer
  la demande sans réserver ni modifier le stock. Le flux produit ainsi le
  fan-out `order-service → inventory-service` et `order-service →
  restock-service`, visible dans APM/Kibana.
- `GET /api/error` sur `order-service` déclenche volontairement une commande
  dont la quantité dépasse toujours le stock disponible, pour observer la
  propagation d'une erreur métier (rupture de stock) entre les deux services.

## Ordre de lecture

1. `pom.xml` : agrégateur Maven et versions communes.
2. `Dockerfile` : build multi-stage ; l'`ENTRYPOINT` des trois images de
   service attache l'agent Java OpenTelemetry, seul agent d'instrumentation.
3. [`kubernetes/apps/supermarket-demo/application.yaml`](../../kubernetes/apps/supermarket-demo/application.yaml) :
   les trois services déclarés comme des Application Crossplane ; la Composition
   (`architecture/platform/crossplane/applications`) produit leurs Deployments, Services et
   l'instrumentation qui configure l'agent OTel et les raccorde au collecteur Edge en OTLP.
4. `order-service/src/main/resources/application.yml`, puis la même
   configuration d'`inventory-service` : endpoints, Kafka, MongoDB,
   PostgreSQL et Actuator.
5. Le code des trois modules pour le flux métier (`order-service/.../order`,
   `inventory-service/.../inventory`, `restock-service/.../restock`).

Construire les images applicatives avec `make apps-build`, puis déployer uniquement
l'application avec `make apps-deploy`. Cette cible applique les Application de
`kubernetes/apps/supermarket-demo/application.yaml` avec le tag `APP_IMAGE_TAG`.

Pour déclencher une commande de recette via le service Kubernetes, exécuter
`make order-service-command`. La cible crée un pod `curl` éphémère, appelle
`POST /api/orders`, affiche la réservation et supprime le pod. Les variables
`ORDER_PRODUCT_ID` et `ORDER_QUANTITY` permettent d'adapter la commande, par
exemple :

```bash
make order-service-command ORDER_PRODUCT_ID=PASTA-500G ORDER_QUANTITY=2
```

## Documentation externe

- [Agent Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/reference/actuator/)

## Versions d'images

Le build Maven est figé sur `maven:3.9.9-eclipse-temurin-21` et les images
d'exécution sur `eclipse-temurin:21.0.7_6-jre-noble`. Toute mise à jour doit
être testée puis effectuée dans une modification dédiée.

La version de l'agent OpenTelemetry est contrôlée par
`OTEL_JAVA_AGENT_VERSION` lors de `make -C architecture apps-build`. Elle est intégrée
dans chaque image applicative et n'est donc pas téléchargée au démarrage des
Pods. Sa configuration déclarative, commune aux trois services, est dans
`kubernetes/apps/supermarket-demo/default/otel/agent.yaml`, chargée par
`OTEL_CONFIG_FILE` dans l'overlay Kubernetes. Les variables
`MANAGEMENT_OTLP_*` restent dans Kubernetes car elles configurent l'exporteur
Micrometer de Spring Boot, distinct de l'agent Java.

Les consommateurs Kafka conservent aussi un mapping de compatibilité pour
l'ancien nom de classe `io.systemlens.supermarket.contract.OrderPlaced`. Les
messages déjà présents dans `supermarket.order.placed` peuvent ainsi être
désérialisés avec le contrat généré actuel, sans suppression du topic.

Le tag des images Docker (`order-service:1.1.6` / `inventory-service:1.1.6` /
`restock-service:1.1.6`,
fixé dans `Makefile` et le manifest Kubernetes de `architecture/`) est géré indépendamment
de `<version>` dans les `pom.xml` (actuellement `1.0.0`, partagée par les trois
modules Maven). Le tag Docker identifie une itération de l'image de
démonstration ; la version Maven identifie une itération du code Java. Un tag
Docker est immuable : choisir un nouveau `APP_IMAGE_TAG` à chaque image. Par
exemple, `make apps-build APP_IMAGE_TAG=1.1.6`, puis
`make images-import apps-deploy APP_IMAGE_TAG=1.1.6`. La cible de déploiement
met explicitement à jour l'image des Deployments et attend leur rollout.

## Graphe d'architecture Java

Cette application est la fixture Java commune au parcours des trois dépôts.
SystemLens en indexe les preuves statiques et génère le graphe HTML, le skill
peut ensuite expliquer ou auditer ce modèle, puis le laboratoire permet de
vérifier le comportement déployé dans Kubernetes et les signaux reçus par
Elastic. Un résultat d’indexation ou d’enrichissement ne constitue donc pas à
lui seul une preuve d’exécution.

Le manifeste courant `architecture.ai-java.pass-004.json` enregistre les faits
relus directement dans les sources Java avec le format
`systemlens-ai-graph-v1`. Il complète l'index AST de SystemLens avec les
modules déployables, les API REST, les canaux Kafka, la collection MongoDB et
les dépendances inter-modules qui ne sont pas résolues automatiquement. Le
rapport `architecture.application-inventory.json` fournit les matrices
directionnelles `module → endpoint`, `endpoint → module`, `module → module`,
`module → module (compilation)`, `module → topic → module` et `module →
collection MongoDB`, chacune avec ses preuves de source et son niveau de
confiance. Le fichier `architecture.codeql-module-dependencies.json` est le
graphe CodeQL des imports Java vers `supermarket-contracts` ; il distingue les
dépendances de compilation des flux REST et Kafka. Le document
`architecture.systemlens-flows.json` conserve les flux potentiels produits par
l'extracteur. Les arêtes enrichies du manifeste référencent ces flows par
`flow_refs`, tandis que les étapes ordonnées restent dans le rapport : elles ne
sont volontairement pas importées comme des arêtes de topologie.

Prérequis : disposer d'une version de `systemlens` qui fournit les commandes
`import-facts` et `export microservices --html`. Depuis la racine du dépôt :

```bash
make apps-architecture-graph
make apps-codeql-module-graph
```

La cible diagnostique et actualise l'index local, vérifie les deux documents
JSON, exporte les flux conservateurs dans `architecture.systemlens-flows.json`,
réconcilie le namespace `ai-java-architecture`, puis génère
`apps/supermarket-demo/architecture.java.html`. Le résumé d'import doit
indiquer 12 faits et l'export doit annoncer 3 services et 8 arêtes. Ouvrir le
fichier HTML et vérifier la présence des trois services, des trois topics
Kafka, de la collection `order_fulfillments` associée à `inventory-service` et
de l'appel REST `POST /api/reservations` entre `order-service` et
`inventory-service`.

La cible CodeQL crée une base temporaire, exécute la requête
`codeql/ModuleDependencies.ql`, puis actualise le graphe de modules et la
matrice `module_to_module_compile_time`. Le résultat attendu contient trois
arêtes confirmées vers `supermarket-contracts` : une depuis chacun des services
applicatifs.
