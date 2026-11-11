# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `architecture/platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`supermarket-demo/README.md`](supermarket-demo/README.md), puis la base
commune et l’overlay par défaut sous `../kubernetes/apps/`, et enfin les modules Maven
communs. L’application est raccordée à l’architecture d’observabilité active.

[`demo-api/README.md`](demo-api/README.md) décrit l'API de démonstration :
un hello world qui forme la plateforme `demo` et produit traces, logs et
métriques JVM par le seul agent Java OTel.

Pour intégrer une nouvelle application Java dans les chaînes APM et OTel
(traces, métriques et logs), suivre [Ajouter une application Java observée](ADDING_APPLICATION.md) ;
`demo-api` en est l'exemple le plus court.
Pour vérifier l’intégration de bout en bout, consulter le
guide de déploiement et d'exploitation de l'architecture active.

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [Agent Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
