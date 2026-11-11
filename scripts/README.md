# Scripts partagés de l’infrastructure

Ce dossier contient les utilitaires d'infrastructure commune qui sont appelés
par le Makefile d'architecture. Les scripts Elastic et Kibana sont dans
`architecture/platform/elk/scripts/`.

## Fichiers

- `cluster-status.sh` : vérifie les conteneurs et les services de
  `supermarket-middleware-01`.
- `check-kafka-jolokia.sh` : contrôle que Jolokia expose les MBeans requis par
  les streams Kafka de la policy Fleet (`make kafka-jolokia-verify`).
- `mongodb-elk-workload.js` : génère une charge MongoDB pour observer le flux
  dans Elastic (`make mongodb-workload`).

Lire d'abord `architecture/ansible/README.md` pour comprendre ce que ces
scripts vérifient.

## Documentation externe

- [Lima](https://lima-vm.io/docs/)
- [MongoDB replica sets](https://www.mongodb.com/docs/manual/replication/)
- [Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
