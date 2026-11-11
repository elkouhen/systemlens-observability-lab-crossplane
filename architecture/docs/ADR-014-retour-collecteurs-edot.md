# ADR-014 : ramener les collecteurs du lab sur EDOT

## Statut

Accepted

Remplace [ADR-006](ADR-006-collecteurs-opentelemetry-contrib.md) pour la
distribution des collecteurs. [ADR-002](ADR-002-edot-standalone-ou-managed-by-fleet.md)
s'applique de nouveau à l'ensemble des collecteurs.

## Date

2026-11-02

## Contexte

ADR-006 avait passé les quatre collecteurs du chemin de données sur
`otel/opentelemetry-collector-contrib` (`0.164.0` en dernier lieu), tandis
que les Elastic Agent des VM restaient en EDOT :

| Collecteur | Emplacement |
| --- | --- |
| `otel-kubernetes` (DaemonSet) | `platform/kubernetes/base/observability/otel-kafka.yaml` |
| `otel-kubernetes-cluster` (Deployment) | même fichier |
| Collecteur Edge | `ansible/roles/otel_edge/` sur `otel-edge-01` |
| Collecteur backend | `ansible/roles/otel_backend/` sur `otel-backend-01` |

Deux lignes de versions coexistaient (Elastic `9.5.4` et contrib), les
collecteurs n'étaient pas couverts par le support Elastic et les composants
propres à Elastic (`elasticapm`, `elasticinframetrics`) n'étaient pas
disponibles.

## Décision

Les quatre collecteurs utilisent l'image
`docker.elastic.co/elastic-agent/elastic-otel-collector`, à la version de la
stack (`elastic_agent_version` pour Edge et backend, valeur figée dans le
manifest Kustomize pour Kubernetes, contrôlée par
`make elastic-version-validate`).

- Les configurations ne changent pas : elles n'utilisent que des composants
  présents dans EDOT `9.5.4` (receivers `otlp`, `kafka`, `hostmetrics`,
  `kubeletstats`, `k8s_cluster`, `prometheus` ; processors `transform`,
  `filter`, `resource`, `k8sattributes`, `cumulativetodelta` ; exporters
  `kafka`, `otlphttp`, `elasticsearch` ; extensions `bearertokenauth`,
  `file_storage`, `health_check`).
- Le conteneur s'exécute avec `elastic-agent` (UID/GID 1000) : le fichier de
  clés Edge et le `file_storage` du backend lui appartiennent.
- La variable `otel_collector_contrib_version` est supprimée.

## Conséquences

- Une seule ligne de versions : la montée de version des collecteurs suit
  celle de la stack Elastic.
- Les collecteurs sont couverts par le support Elastic ; `elasticapm` ou
  `elasticinframetrics` peuvent être ajoutés sans changer de distribution.
- L'image est plus lourde que contrib, et une correction upstream n'est
  disponible qu'avec une version EDOT qui l'embarque.

## Vérification

Les configurations Edge, backend et `otel-kubernetes-cluster` passent
`validate` avec l'image EDOT `9.5.4` ; celle du DaemonSet aussi, à
l'exception de `kubeletstats`, qui exige l'API Kubernetes. Après
déploiement :

```bash
make elastic-version-validate kubernetes-validate ansible-validate
make otel-backend-vm-provision otel-edge-vm-provision kubernetes-observability-deploy
make dashboards-verify
```

Résultat attendu : les quatre collecteurs tournent sur l'image EDOT, le lag
du groupe `otel-backend` reste proche de 0 et les data streams applicatifs,
Kubernetes et VM restent alimentés.
