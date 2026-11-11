# Module inventory-service : gestion du stock

Ce module reçoit les commandes (via Kafka pour les commandes en ligne, via REST
pour les commandes en caisse), vérifie et décrémente le stock du produit
demandé, puis sauvegarde le résultat dans MongoDB (journal d'audit
`order_fulfillments`) et PostgreSQL (registre `stock_movements` et catalogue
`products`). Les deux écritures partagent le même identifiant de commande ; si
l'écriture PostgreSQL échoue, l'écriture MongoDB et la décrémentation de stock
sont compensées. Une quantité demandée supérieure au stock disponible déclenche
une rupture de stock (`OutOfStockException`, HTTP 409). Lire
`src/main/resources/application.yml` avant les classes du package `inventory`
pour comprendre les adresses de connexion et le nom du consumer group.

Le schéma PostgreSQL est créé au démarrage par Flyway dans
`src/main/resources/db/migration/V1__create_inventory_schema.sql`. Hibernate est
en mode `validate` : il vérifie que les tables `products` et `stock_movements`
correspondent à la migration sans modifier le schéma. Sur une base existante
sans historique Flyway, `baseline-on-migrate` l'enregistre au niveau `0` afin de
préserver les données déjà présentes ; une base vierge exécute la migration
`V1` automatiquement.

L'agent Java OpenTelemetry, attaché par le Dockerfile parent, produit les
traces des interactions Kafka, MongoDB et PostgreSQL sans modifier le code de
ce module.
Les transactions Kafka sont exposées directement avec le type `messaging` dans
la vue APM.

Chaque réservation produit un log métier : `INFO` en cas de succès et
`WARN` pour une quantité invalide, un produit absent ou une rupture de stock.
Lorsqu'une réservation épuise le stock, le service publie
`supermarket.stock.depleted`. `restock-service` répond par une demande sur
`supermarket.stock.restock-requested`, appliquée ici afin que ce module reste
propriétaire du catalogue PostgreSQL.
L'agent OTel exporte ces logs en OTLP vers
`logs-generic.otel-supermarche_homologation` (ADR-012), avec le `trace_id` et le
`span_id` du span courant. Les paires `addKeyValue` (`event.action`,
`product.id`, `business.units_sold`...) deviennent des attributs du log. La
vue Logs des transactions APM les retrouve par l'alias `trace.id`.

Le service expose aussi le compteur métier Micrometer
`business.orders.completed`, incrémenté après la réussite des écritures
MongoDB et PostgreSQL. Le tag `channel` distingue les commandes `rest` et
`kafka`. Dans l’architecture active, la métrique est exportée directement en OTLP par
Micrometer et stockée dans le data stream `metrics-*.otel-*`.

La même réussite produit l'événement structuré
`event.action=product_sale_completed`. Les champs `product.id`, `product.name`,
`business.units_sold` et `sales.channel` permettent de mesurer les unités
vendues sans assimiler une commande à une unité. Cet événement n'est pas émis
si une écriture de persistance échoue.

## Architecture hexagonale

Le service est également déclaré comme application Spring Modulith. Les
packages directs `domain`, `application` et `adapter` constituent les modules
fonctionnels détectés sous `InventoryServiceApplication`. La vérification
Spring Modulith est exécutée par `ArchitectureTest` afin de détecter les
dépendances interdites et les cycles entre ces modules ; elle complète les
règles ArchUnit de l'architecture hexagonale.

Le module sépare le métier des frameworks et des systèmes externes :

- `domain/` contient les règles métier du stock et ne dépend pas de Spring,
  JPA, MongoDB ou Kafka ;
- `application/` contient le cas d’usage de réservation et les ports entrants
  et sortants ;
- `adapter/in/` contient les adaptateurs REST et Kafka ;
- `adapter/out/` contient les adaptateurs de persistance JPA/MongoDB et de
  publication Kafka.

Toute évolution du stockage ou du transport doit rester dans un adaptateur.
Le cas d’usage ne doit dépendre que des ports et du domaine, afin de préserver
la testabilité et de permettre de remplacer une technologie sans modifier les
règles métier.

Le modèle de domaine doit rester propriétaire des invariants du stock :
`Product` est l'agrégat racine, `Quantity` est le value object des quantités
strictement positives et `StockReservation` représente le résultat métier d'une
réservation. Les contrôleurs, consommateurs Kafka et adapters de persistance
ne doivent pas reproduire ces règles. Les mesures techniques comme la durée
d'exécution sont produites par la couche application ; elles ne doivent pas
être simulées dans le domaine.

Les règles d'architecture sont vérifiées par ArchUnit dans
`src/test/java/io/systemlens/supermarket/inventory/ArchitectureTest.java`.
Elles garantissent notamment l'indépendance du domaine vis-à-vis des
frameworks, l'absence de dépendance de l'application vers les adapters, des
ports sous forme d'interfaces et la finalité des types du domaine. Les exécuter
avec :

```bash
mvn -pl inventory-service -am verify
```

Le plugin Maven `exec-maven-plugin` lance `ModulithC4ModelGenerator` pendant
`package`. Celui-ci utilise le `Documenter` officiel de Spring Modulith pour
produire le modèle C4 PlantUML et AsciiDoc dans
`inventory-service/target/spring-modulith-c4/`. Le plugin
`asciidoctor-maven-plugin` transforme ensuite `all-docs.adoc` en rapport HTML
`inventory-service/target/spring-modulith-c4-html/all-docs.html`, avec les
diagrammes C4 intégrés. La génération complète est incluse dans :

```bash
mvn -pl inventory-service -am package
```

## API OpenAPI

Le modèle de données de l'inventaire est volontairement séparé en trois couches :

- `domain/Product.java` est le modèle métier et porte les invariants du stock ;
- `adapter/out/persistence/jpa/ProductEntity.java` et
  `StockMovementEntity.java` sont les modèles de stockage ;
- `adapter/in/web/ProductResponseDto.java` est le modèle de mapping de l'API,
  tandis que le contrat OpenAPI reste le modèle public de l'API.

L'adapter API convertit le modèle métier vers le modèle d'API. Le domaine ne
dépend ni de Spring, ni de JPA, ni des classes OpenAPI générées.

Le contrat API First est versionné dans `src/main/resources/static/openapi.yaml`.
Maven le valide avant la compilation ; toute évolution d'endpoint ou de payload
commence donc par ce fichier. Avec le service démarré localement, le contrat est
servi sur `http://localhost:3001/openapi.yaml` et consultable avec Swagger UI
sur `http://localhost:3001/swagger-ui.html`. Vérifier que l'interface liste
`POST /api/reservations` et ses réponses `400`, `404` et `409`.

À la phase Maven `generate-sources`, OpenAPI Generator produit l'interface
Spring et les DTO sous `target/generated-sources/openapi`. `InventoryController`
implémente cette interface ; ne jamais modifier ni versionner les sources
générées.

## API AsyncAPI

Le contrat API First Kafka est versionné dans
`src/main/resources/static/asyncapi.yaml`. Il définit la consommation de
`OrderPlaced`, la publication de `StockDepleted` et la consommation de
`StockRestockRequested`, avec les groupes Kafka effectivement configurés. Le
fichier est servi sur `http://localhost:3001/asyncapi.yaml`. Le plugin Maven
AsyncAPI génère les modèles Java sous `target/generated-sources/asyncapi`,
employés par les adaptateurs Kafka. La validation et la génération s'exécutent
avec `mvn verify`; ne jamais modifier ni versionner les sources générées.

## Documentation externe

- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Spring Data MongoDB](https://docs.spring.io/spring-data/mongodb/reference/)
- [Spring Data JPA](https://docs.spring.io/spring-data/jpa/reference/)
