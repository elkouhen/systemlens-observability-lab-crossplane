# Module restock-service : réassort asynchrone

Ce microservice consomme l'événement Kafka `supermarket.stock.depleted` et
publie une demande de 500 unités sur
`supermarket.stock.restock-requested`. Il ne lit ni n'écrit dans les bases de
données : `inventory-service` reste propriétaire du catalogue PostgreSQL et
applique la demande de réassort.

Il consomme également `supermarket.order.placed` avec le groupe
`restock-order-observer`. Cette consommation est volontairement en lecture
seule : elle rend visible le fan-out d'une commande en ligne vers
`inventory-service` et `restock-service` sans réserver le stock une seconde
fois. Le compteur `business.orders.observed` et le log associé permettent
de vérifier le flux dans Kibana.

Le module est instrumenté par l'agent Java OpenTelemetry attaché par le
Dockerfile parent, qui exporte aussi ses logs en OTLP (ADR-012) : ils
permettent de suivre l'épuisement et le réassort d'un produit dans Kibana.

Le compteur Micrometer `business.stock.restock.requested` est incrémenté pour
chaque demande de réassort émise sur Kafka. Le compteur
`business.stock.restock.completed`, porté par `inventory-service`, est
incrémenté uniquement après l'application réussie du réassort dans PostgreSQL.
La différence entre les deux compteurs permet de repérer une demande Kafka non
appliquée.

Vérifier le module avec l'ensemble du projet :

```bash
make apps-test
```
