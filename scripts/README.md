# Scripts partagés de l’infrastructure

Ce dossier contient les utilitaires d'infrastructure commune qui sont appelés
par le Makefile d'architecture. Les scripts Elastic et Kibana sont dans
`architecture/platform/elk/scripts/`.

## Fichiers

- `mongodb-elk-workload.js` : génère une charge MongoDB pour observer le flux
  dans Elastic (`make mongodb-workload`, exécuté dans le pod de l'instance
  MongoDB de `k3s-01` avec le compte `observability`).

L'état des VM et des clusters se lit avec `make vm-status` et
`make vm-services-status`.

Lire d'abord `architecture/ansible/README.md` pour comprendre ce que ces
scripts vérifient.

## Documentation externe

- [Lima](https://lima-vm.io/docs/)
- [MongoDB replica sets](https://www.mongodb.com/docs/manual/replication/)
- [Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
