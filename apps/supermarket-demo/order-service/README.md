# Module order-service : commandes du supermarché

Ce module simule la prise de commande côté supermarché. Il expose une API HTTP
pour passer une commande en caisse (`POST /api/orders`, appel synchrone vers
`inventory-service`) et publie périodiquement des commandes en ligne sur Kafka
(commandes traitées en tâche de fond par `inventory-service`). Commencer par
`src/main/resources/application.yml`, qui définit les propriétés Spring, Kafka
et Actuator, puis lire les contrôleurs et le planificateur dans
`src/main/java`.

Les traces sont produites par l'agent Java OpenTelemetry, attaché au démarrage
du conteneur, et envoyées en OTLP au collecteur Edge ; elles ne nécessitent
aucun SDK dans ce module. L'Application Crossplane `order-service`
(`architecture/gitops/supermarket/applications.yaml`) configure l'agent : identité du service, environnement et clé du collecteur.

## API OpenAPI

Le contrat API First est versionné dans `src/main/resources/static/openapi.yaml`.
Maven le valide avant la compilation ; toute évolution d'endpoint ou de payload
commence donc par ce fichier. Avec le service démarré localement, le contrat est
servi sur `http://localhost:3000/openapi.yaml` et consultable avec Swagger UI
sur `http://localhost:3000/swagger-ui.html`. Vérifier que l'interface liste les
opérations `POST /api/orders`, `GET /api/error` et `GET /api/health`.

À la phase Maven `generate-sources`, OpenAPI Generator produit l'interface
Spring et les DTO sous `target/generated-sources/openapi`. `OrderController`
implémente cette interface ; ne jamais modifier ni versionner les sources
générées.

## API AsyncAPI

Le contrat API First Kafka est versionné dans
`src/main/resources/static/asyncapi.yaml`. Il définit la publication de
`OrderPlaced` sur `supermarket.order.placed`, avec `orderId` comme clé Kafka.
Le fichier est servi sur `http://localhost:3000/asyncapi.yaml`. Le plugin Maven
AsyncAPI génère son modèle Java sous `target/generated-sources/asyncapi`, employé
par le producteur Kafka. La validation et la génération s'exécutent avec
`mvn verify`; ne jamais modifier ni versionner les sources générées.

## Documentation externe

- [Spring Boot externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [Spring for Apache Kafka](https://docs.spring.io/spring-kafka/reference/)
- [Agent Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
