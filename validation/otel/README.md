# Validation OpenTelemetry

Ce projet Ansible envoie une métrique OTLP/HTTP avec un marqueur unique, puis
attend son indexation dans Elasticsearch. Le parcours est exécuté en SSH sur
la machine du groupe `otel_collectors`. Comme Kibana Discover lit ces index, le playbook vérifie
également que l'API Kibana est joignable et affiche le marqueur à rechercher
dans Discover.

Le parcours validé dans l’architecture active est :

- `edge-directe-ssh` : playbook SSH sur `k3s-01` → Collecteur EDOT Edge (pod `otel-edge`,
  port d'hôte `192.168.33.50:4318`) → Kafka OTel de `k3s-01` (`otel-metrics-elk-homologation`) →
  collecteur backend de `k3s-01` → data stream
  `metrics-generic.otel-elk_homologation` avec `platform.id` = `elk` → Kibana.
  La métrique déclare `platform.id` = `elk` et
  `deployment.environment.name` = `homologation` : sans plateforme servie par
  l'Edge, il la rejetterait (ADR-020).

## Prérequis

- Ansible, Lima et la VM `k3s-01` démarrée, avec le Collecteur Edge déployé ;
- un compte Elasticsearch ayant le droit de lire `metrics-*` ;
- le mot de passe Elasticsearch et la clé Bearer `OTEL_EDGE_KEY_ELK_01`
  (la validation se présente comme la VM `elk-01`, plateforme `elk`), fournis uniquement par
  l'environnement. `make otel-validation` les charge depuis le fichier
  d'identifiants du lab et le secret Kubernetes ; pour lancer le playbook
  directement :

  ```bash
  source ./architecture/platform/elk/scripts/load-credentials.sh
  source ./architecture/.observability-credentials.env
  ```

## Paramétrage de l'inventaire

L'inventaire fournit les hôtes, leurs paramètres de connexion Ansible et
`otel_gateway_direct_endpoint`. Les URL Elastic, les paramètres de validation
et les identifiants sont définis dans `playbook.yml`.

Ne pas inscrire `elasticsearch_password` dans l'inventaire : sa valeur est
lue depuis `ELASTICSEARCH_PASSWORD`.

## Exécution et résultat attendu

Depuis la racine du dépôt :

```bash
make otel-validation
```

Le playbook porte le tag `host`. Sans tag, le parcours SSH est exécuté.

| Tag | Parcours validé | Commande |
| --- | --- | --- |
| `host` | Depuis le collecteur, directement vers le Gateway local | `make otel-validation VALIDATION_TAGS=host` |

Les tags sont transmis à Ansible avec `--tags`. Une valeur inconnue ne
sélectionne aucun play et ne constitue pas une validation.

Depuis ce répertoire, Ansible utilise directement `ansible.cfg` et son
inventaire par défaut :

```bash
source ../../architecture/platform/elk/scripts/load-credentials.sh
ansible-playbook playbook.yml
```

Pour un inventaire distinct :

```bash
make otel-validation INVENTORY=validation/otel/inventory/mon-environnement.yml
```

Le playbook réussit uniquement après avoir reçu une réponse OTLP réussie, un
statut `200` de Kibana et un document correspondant au marqueur dans `metrics-*`.
Il affiche alors le marqueur exact à coller dans Kibana Discover.
