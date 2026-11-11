# Contrats partagés

Ce module contient les modèles générés depuis le contrat AsyncAPI partagé entre
`order-service`, `inventory-service` et `restock-service`. Il ne porte aucune
configuration d'infrastructure : son rôle est de stabiliser le format des
messages Kafka et des appels REST utilisés par les applications.

Le code Java est généré pendant la phase Maven `generate-sources` à partir de
`inventory-service/src/main/resources/static/asyncapi.yaml`. Lire d'abord le
type `OrderPlaced` (identifiant de commande, produit, quantité, horodatage),
puis `StockDepleted` et `StockRestockRequested` pour le flux de réassort
asynchrone. `OrderPlaced` est publié par `order-service` et consommé
par `inventory-service` ainsi que, en lecture seule, par `restock-service` pour
illustrer un fan-out Kafka observable.

## Documentation externe

- [Modéliser des événements Kafka](https://kafka.apache.org/documentation/#design)
