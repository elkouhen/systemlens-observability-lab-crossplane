# Applications

Ce répertoire contient le code et les manifests propres aux workloads métier.
Il est volontairement séparé de `architecture/platform/` : une application ne doit pas
porter la configuration de la plateforme ELK qui l'observe.

## Parcours conseillé

Lire [`supermarket-demo/README.md`](supermarket-demo/README.md), puis son groupe
de déploiement `../architecture/gitops/supermarket/` (Application, bases, Secrets), et enfin les modules Maven
communs. L’application est raccordée à l’architecture d’observabilité active.

[`demo-api/README.md`](demo-api/README.md) décrit l'API de démonstration :
un hello world qui forme la plateforme `demo` et produit traces, logs et
métriques JVM par le seul agent Java OTel.

Pour intégrer une nouvelle application Java dans les chaînes APM et OTel
(traces, métriques et logs), suivre [Ajouter une application Java observée](ADDING_APPLICATION.md) ;
`demo-api` en est l'exemple le plus court.
Pour vérifier l’intégration de bout en bout, consulter le
guide de déploiement et d'exploitation de l'architecture active.

## Livraison d'une nouvelle version

Les images ne sont plus construites sur le poste : GitHub les construit et les publie.

1. Modifier le code sous `apps/`.
2. Choisir un nouveau tag (un tag est immuable) et l'inscrire dans le manifest du groupe :
   `architecture/gitops/supermarket/applications.yaml` (`image: {name: order-service, tag: …}`) ou
   `architecture/gitops/demo-api/application.yaml`.
3. Committer et pousser sur `main`.
4. Le workflow [`build-images.yml`](../.github/workflows/build-images.yml) exécute `mvn verify`,
   construit les images arm64 (runner `ubuntu-24.04-arm`, comme les VM Lima) et les publie sur
   `ghcr.io/elkouhen/systemlens-observability-lab-crossplane/<image>` avec le tag de Git et
   `sha-<commit court>`.
5. Argo CD synchronise le nouveau tag ; la Composition `Application` redéploie le service, qui tire
   l'image publique de GHCR (`imagePullPolicy: IfNotPresent`).

`make images-wait` (appelé par `make deploy`) attend que GHCR serve, sans authentification, les
images aux tags déclarés dans Git. Les cibles `make apps-build`, `make images-import`,
`make demo-api-build` et `make demo-api-import` restent disponibles pour essayer une image locale
sans la publier : elles l'étiquettent avec le nom GHCR et l'importent dans `k3s-01`, où
`IfNotPresent` la préfère au registre.

## Documentation externe

- [Déployer des workloads Kubernetes](https://kubernetes.io/docs/concepts/workloads/)
- [Agent Java OpenTelemetry](https://opentelemetry.io/docs/zero-code/java/agent/)
