# Applications Kubernetes

Chaque application est déclarée par un fichier `application.yaml` : une ou plusieurs
`Application` Crossplane (XRD et Composition dans `architecture/platform/crossplane/applications`).
La Composition produit le Deployment, le Service et l'instrumentation OTel de chaque service,
avec les mêmes noms, namespaces, labels et variables que les anciens manifests Kustomize.

- `apps/supermarket-demo/application.yaml` : order, inventory et restock-service ;
- `apps/demo-api/application.yaml` : API de démonstration des signaux ;
- `apps/*/default/otel/agent.yaml` : configuration déclarative de l'agent Java OTel, incorporée
  dans l'Application par `architecture/platform/crossplane/scripts/applications.py`.

Les namespaces et les Secrets applicatifs sont des Object Crossplane
(`architecture/platform/crossplane/kubernetes/secrets.yaml`). Les manifests de la plateforme
d'observabilité sont dans `architecture/platform`.

Validation depuis `architecture/` :

```bash
make kubernetes-validate
```

Les cibles `make apps-deploy` et `make demo-api-deploy` appliquent les Application.
