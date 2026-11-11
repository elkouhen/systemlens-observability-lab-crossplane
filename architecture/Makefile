SHELL := /bin/bash
.DEFAULT_GOAL := help

KUBECTL ?= kubectl
# Les VM sont des instances Lima (lima/), pilotées par scripts/vm (création, provisionnement Ansible, shell).
VM ?= $(CURDIR)/scripts/vm
export VM
K3D_CLUSTER ?= elastic
K3S_VM_NAME ?= k3s-01
# Accès depuis l'hôte par les redirections de port Lima (lima/*.yaml), le réseau 192.168.33.0/24
# n'étant joignable qu'entre VM.
K3S_VM_IP ?= 127.0.0.1
K3S_KUBECONFIG ?= $(ARCH_ROOT)/.kube/k3s.config
export KUBECONFIG ?= $(K3S_KUBECONFIG)
APP_MANIFEST_ROOT ?= ../kubernetes/apps/supermarket-demo
VALIDATION_ROOT ?= ../validation/otel
SHARED_SCRIPTS_ROOT ?= ../scripts
DEPLOYMENT_PROFILE := minimal
ARCH_NAME := Hybride Fleet
ARCH_ROOT := .
K8S_NAMESPACE ?= elastic-stack
APP_NAMESPACE ?= h0tl-supermarche-app
APP_IMAGE_TAG ?= 1.1.6
# API de démonstration hello world (apps/demo-api), plateforme demo.
DEMO_API_MANIFEST_ROOT ?= ../kubernetes/apps/demo-api
DEMO_API_NAMESPACE ?= h0tl-demo-app
DEMO_API_IMAGE_TAG ?= 1.1.1
DEMO_API_PATH ?= /api/hello?name=lab
OTEL_JAVA_AGENT_VERSION ?= 2.28.1
ORDER_PRODUCT_ID ?= PASTA-500G
ORDER_QUANTITY ?= 1
ELASTIC_STACK_VERSION ?= 9.5.4
KUBERNETES_OTEL_PACKAGE_VERSION ?= 2.6.1
KAFKA_OTEL_PACKAGE_VERSION ?= 0.3.1
POSTGRESQL_OTEL_PACKAGE_VERSION ?= 0.5.0
MONGODB_OTEL_PACKAGE_VERSION ?= 0.3.1
SYSTEM_OTEL_PACKAGE_VERSION ?= 0.3.0
OTEL_COLLECTOR_INTERNAL_TELEMETRY_PACKAGE_VERSION ?= 1.2.3
SKIP_ELK_VM_PROVISION ?= 0
SKIP_KUBERNETES_APPLY ?= 0
ELASTICSEARCH_URL ?= http://elasticsearch.observability.test:9200
KIBANA_URL ?= http://kibana.observability.test:5601
KIBANA_HOST ?= kibana.observability.test
KIBANA_CURL_RESOLVE ?= kibana.observability.test:5601:127.0.0.1
ELASTICSEARCH_CURL_RESOLVE ?= elasticsearch.observability.test:9200:127.0.0.1
FLEET_URL ?= http://fleet.observability.test:8220
FLEET_CURL_RESOLVE ?= fleet.observability.test:8220:127.0.0.1
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent) au format
# PEM. Laisser vide sur une machine sans interception TLS : voir certs/README.md.
# Racine de confiance du proxy TLS d'entreprise : le certificat local
# certs/zscaler-root-ca.crt (ignoré par Git) est utilisé s'il existe, sauf
# valeur explicite de ZSCALER_CA_CERT. Vide sans interception TLS.
ZSCALER_CA_CERT ?= $(wildcard $(abspath $(CURDIR)/../certs/zscaler-root-ca.crt))
export ZSCALER_CA_CERT
K3D_CA_DEST ?= /usr/local/share/ca-certificates/zscaler-root-ca.crt
C4_PAGES_BASE ?= ./
OBSERVABILITY_CREDENTIALS_FILE ?= $(ARCH_ROOT)/.observability-credentials.env
# Clés Bearer des clients du collecteur Edge (ADR-015) : une par VM rattachée
# à l'Edge (OTEL_EDGE_KEY_<HOST>) et une par collecteur Kubernetes.
OTEL_EDGE_KEYS := OTEL_EDGE_KEY_K3S_01 OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE_01 OTEL_EDGE_KEY_ELK_01 OTEL_EDGE_KEY_OTEL_EDGE_01 \
	OTEL_EDGE_KEY_KUBERNETES OTEL_EDGE_KEY_KUBERNETES_CLUSTER

# Interface opérateur principale. Les cibles techniques non listées restent
# disponibles pour les dépendances et les diagnostics ciblés, sans apparaître
# dans l'aide courante.
HELP_TARGETS := help architecture-status credentials-show credentials-generate cluster-show \
	platform-status kubernetes-status vm-status vm-services-status vm-services-restart time-sync-apply time-sync-verify \
	apps-build apps-test command-center-build \
	kubernetes-validate ansible-validate otel-config-validate elastic-version-validate ci-run \
	vms-start vms-restart vms-destroy cache-status cache-clean \
	architecture-deploy \
	elk-deploy fleet-assets-deploy apps-deploy \
	application-data-verify order-service-command demo-api-build demo-api-deploy demo-api-call demo-api-jvm-metrics-verify \
	dashboards-verify trace-context-verify observability-schema-verify otel-routing-verify otel-kafka-acl-verify \
	otel-validate retention-validate retention-deploy retention-verify \
	stock-show middleware-vm-provision k3s-vm-provision order-service-logs-follow inventory-service-logs-follow restock-service-logs-follow

.PHONY: demo-api-test demo-api-build demo-api-import demo-api-deploy demo-api-call demo-api-jvm-metrics-verify demo-api-logs-follow help architecture-status c4-pages-build credentials-show credentials-generate cluster-info platform-status kubernetes-status java-version-verify apps-build apps-test command-center-build images-import kubernetes-validate ansible-validate otel-config-validate otel-routing-verify otel-legacy-datastreams-delete elastic-version-validate slides elastic-stack-deploy otel-elasticsearch-credentials-apply \
	elk-deploy kibana-fleet-config-deploy fleet-assets-deploy fleet-prerequisites fleet-registry-ready fleet-server-start fleet-opamp-enable apm-data-view-deploy business-dashboard-deploy business-dashboard-replace apps-deploy fleet-sync \
	observability-policies-validate observability-policies-deploy time-sync-verify \
	mongodb-workload otel-gateway-vm-status otel-backend-vm-provision otel-backend-vm-status \
	otel-validation kubernetes-observability-deploy metrics-chain-restart \
	otel-edge-vm-provision elastic-agent-vm-provision elastic-agent-backend-provision \
	middleware-vm-provision \
	vms-up vms-restart vms-destroy deploy deploy-post elasticsearch-ready kibana-ready apm-kibana-role-apply \
	dashboards-verify otel-flow-dashboard-deploy kubernetes-otel-dashboards-verify trace-context-verify observability-schema-verify apm-report-api-key-create \
	elastic-password-show kibana-password-show elasticsearch-api-key-create \
	beats-api-key-create stock-view application-data-verify order-service-command order-service-logs-follow inventory-service-logs-follow restock-service-logs-follow k3d-ca-import k3s-vm-up k3s-vm-provision k3s-kubeconfig public-tls-apply ci

.PHONY: cluster-show elasticsearch-wait kibana-wait fleet-prerequisites-validate fleet-registry-wait \
	vms-start architecture-deploy deployment-finalize otel-validate ci-run stock-show slides-start \
	crossplane-kubernetes-apply crossplane-kubernetes-wait crossplane-secrets-wait crossplane-mongodb-wait \
	cache-status cache-clean cache-save-k3s-images

##@ Informations et diagnostic

help: ## Afficher les tâches disponibles
	@awk -v targets='$(HELP_TARGETS)' 'BEGIN { FS = ":.*##"; split(targets, names, /[[:space:]]+/); for (name in names) wanted[names[name]] = 1; printf "Usage: make <cible>\n" } /^##@/ { section = substr($$0, 5); if (!(section in section_seen)) sections[++section_count] = section; section_seen[section] = 1; next } /^[a-zA-Z0-9_.-]+:.*##/ && ($$1 in wanted) { item_count[section]++; item_name[section, item_count[section]] = $$1; item_description[section, item_count[section]] = $$2 } END { for (section_index = 1; section_index <= section_count; section_index++) { section = sections[section_index]; for (i = 1; i <= item_count[section]; i++) for (j = i + 1; j <= item_count[section]; j++) if (item_name[section, j] < item_name[section, i]) { tmp = item_name[section, i]; item_name[section, i] = item_name[section, j]; item_name[section, j] = tmp; tmp = item_description[section, i]; item_description[section, i] = item_description[section, j]; item_description[section, j] = tmp } if (item_count[section] > 0) { printf "\n%s\n", section; for (i = 1; i <= item_count[section]; i++) printf "  %-32s %s\n", item_name[section, i], item_description[section, i] } } }' $(MAKEFILE_LIST)

architecture-status: ## Afficher la configuration de l'architecture
	@printf 'ARCH_NAME=%s\nELASTIC_STACK_VERSION=%s\nARCH_ROOT=%s\n' '$(ARCH_NAME)' '$(ELASTIC_STACK_VERSION)' '$(ARCH_ROOT)'

c4-pages-build: ## Construire le site LikeC4 destiné à GitHub Pages
	@npx --yes likec4@1.53.0 build -o dist/c4 --base '$(C4_PAGES_BASE)' --use-hash-history docs
	@mv dist/c4/index.html dist/c4/c4.html
	@cp docs/site/index.html dist/c4/index.html
	@mkdir -p dist/c4/assets
	@cp docs/site/assets/c4-telemetry.png dist/c4/assets/c4-telemetry.png

credentials-show: ## Indiquer comment charger les identifiants dans le shell courant
	@printf 'source ./$(ARCH_ROOT)/platform/elk/scripts/generate-otel-edge-keys.sh\n'
	@printf 'source ./$(ARCH_ROOT)/platform/elk/scripts/load-credentials.sh\n'

credentials-generate: ## Générer ou compléter le fichier local d’identifiants
	@OBSERVABILITY_CREDENTIALS_FILE='$(OBSERVABILITY_CREDENTIALS_FILE)' bash -c 'source ./$(ARCH_ROOT)/platform/elk/scripts/generate-otel-edge-keys.sh'

cluster-info:
	@printf 'KIBANA_URL=%s\nELASTICSEARCH_URL=%s\nFLEET_URL=%s\nUSER=elastic\n' \
		'$(KIBANA_URL)' '$(ELASTICSEARCH_URL)' 'https://fleet.observability.test'

cluster-show: cluster-info ## Afficher les URL et identifiants de l'environnement ELK local

platform-status: kubernetes-status vm-status ## Vérifier Kubernetes et les VM

kubernetes-status: ## Afficher l’état Elastic et applications
	@$(KUBECTL) -n $(K8S_NAMESPACE) get service,ingressroute
	@$(KUBECTL) -n $(APP_NAMESPACE) get deployment,pods

vm-status: ## Vérifier l'état des VM Lima et leurs services spécifiques
	@$(VM) status supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 $(K3S_VM_NAME)
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' MIDDLEWARE_VM_NAME='supermarket-middleware-01' $(SHARED_SCRIPTS_ROOT)/cluster-status.sh
	@$(VM) shell otel-backend-01 'sudo systemctl is-active observability-otel-kafka observability-otel-backend && sudo podman exec -e KAFKA_OPTS= observability-otel-kafka /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 --command-config /opt/kafka/config/otel-kafka-client.properties describe --status'

vm-services-status: ## Afficher l'état des services de chaque VM et des workloads Kubernetes
	@./scripts/vm-services-status.sh

vm-services-restart: ## Redémarrer les services des VM puis les workloads Kubernetes
	@./scripts/vm-services-restart.sh

time-sync-apply: ## Appliquer la configuration chrony et le timer de reprise après suspension sur les cinq VM
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i $(ARCH_ROOT)/ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/time-sync.yml

time-sync-verify: ## Vérifier la synchronisation chrony des cinq VM
	@set -euo pipefail; for node in supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 $(K3S_VM_NAME); do \
		echo "--- $$node ---"; \
		output="$$($(VM) shell "$$node" 'sudo chronyc tracking; sudo chronyc sources -n' 2>/dev/null)"; \
		echo "$$output" | grep -E '^(Reference ID|Stratum|System time|Leap status)' || { echo "État chrony incomplet sur $$node" >&2; exit 1; }; \
		echo "$$output" | awk '/^System time/ { offset=$$4; if (offset < 0) offset=-offset; if (offset > 5) exit 1 }' || { echo "Horloge trop décalée sur $$node" >&2; exit 1; }; \
		echo "$$output" | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal' || { echo "Horloge non synchronisée sur $$node" >&2; exit 1; }; \
		echo "$$output" | grep -Eq '^\^([*+])' || { echo "Aucune source NTP sélectionnée sur $$node" >&2; exit 1; }; \
	done
	@echo 'Les cinq VM sont synchronisées par chrony.'

##@ Construction et préparation locale

apps-build: ## Construire les images applicatives avec l'agent Java OpenTelemetry
	@zscaler_ca_b64=""; \
	if [ -n "$(ZSCALER_CA_CERT)" ]; then \
	  test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }; \
	  zscaler_ca_b64="$$(base64 < "$(ZSCALER_CA_CERT)" | tr -d '\n')"; \
	fi; \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target order-service -t order-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target inventory-service -t inventory-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo && \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target restock-service -t restock-service:$(APP_IMAGE_TAG) ../apps/supermarket-demo

java-version-verify: ## Vérifier que Maven utilise Java 21
	@major="$$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)"; \
	test "$$major" = 21 || { echo "Java 21 requis pour les tests Maven, version détectée : $${major:-inconnue}" >&2; exit 1; }

apps-test: java-version-verify ## Exécuter les tests unitaires et d'intégration Maven des applications
	@mvn --batch-mode verify -f ../apps/supermarket-demo/pom.xml
	@mvn --batch-mode verify -f ../apps/demo-api/pom.xml

##@ API de démonstration des signaux (apps/demo-api)

demo-api-test: java-version-verify ## Exécuter les tests Maven de demo-api
	@mvn --batch-mode verify -f ../apps/demo-api/pom.xml

demo-api-build: ## Construire l'image demo-api avec l'agent Java OpenTelemetry
	@zscaler_ca_b64=""; \
	if [ -n "$(ZSCALER_CA_CERT)" ]; then \
	  test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }; \
	  zscaler_ca_b64="$$(base64 < "$(ZSCALER_CA_CERT)" | tr -d '\n')"; \
	fi; \
	docker build --build-arg ZSCALER_CA_CERT_B64="$$zscaler_ca_b64" --build-arg OTEL_JAVA_AGENT_VERSION=$(OTEL_JAVA_AGENT_VERSION) --target demo-api -t demo-api:$(DEMO_API_IMAGE_TAG) ../apps/demo-api

demo-api-import: ## Importer l'image demo-api dans k3s
	@docker save demo-api:$(DEMO_API_IMAGE_TAG) | $(VM) shell $(K3S_VM_NAME) 'sudo /usr/local/bin/k3s ctr images import -'

demo-api-deploy: crossplane-secrets-wait ## Déployer demo-api dans h0tl-demo-app et attendre son rollout
	@# Application Crossplane (platform/crossplane/applications), tag fixé par DEMO_API_IMAGE_TAG.
	@$(call CROSSPLANE_APPLY_PRUNE,$(CROSSPLANE_APPLICATIONS) $(DEMO_API_MANIFEST_ROOT)/application.yaml,applications.apps.lab.io,applications)
	@$(KUBECTL) -n $(DEMO_API_NAMESPACE) wait --for=condition=Ready applications.apps.lab.io/demo-api --timeout=$(CROSSPLANE_TIMEOUT)
	@$(KUBECTL) -n $(DEMO_API_NAMESPACE) rollout status deployment/demo-api --timeout=180s

demo-api-call: ## Appeler demo-api depuis le cluster (DEMO_API_PATH=/api/hello?name=lab|/api/fail?reason=demo)
	@pod_name="demo-api-call-$$(date +%s)"; \
	$(KUBECTL) -n $(DEMO_API_NAMESPACE) run "$$pod_name" --image=curlimages/curl:8.12.1 \
		--restart=Never --rm --attach -i --command -- \
		curl --silent --show-error -w '\nHTTP %{http_code}\n' "http://demo-api:3010$(DEMO_API_PATH)"

demo-api-jvm-metrics-verify: ## Vérifier les métriques JVM OTel natives de demo-api (5 dernières minutes, ADR-018)
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	 status=0; \
	 for metric in jvm.memory.used jvm.memory.limit jvm.gc.duration jvm.thread.count jvm.class.count jvm.cpu.recent_utilization; do \
	   count="$$(curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
	     -u "elastic:$$es_password" -H 'Content-Type: application/json' \
	     '$(ELASTICSEARCH_URL)/metrics-generic.otel-demo_*/_count' \
	     --data "{\"query\":{\"bool\":{\"filter\":[{\"term\":{\"resource.attributes.service.name\":\"demo-api\"}},{\"exists\":{\"field\":\"metrics.$$metric\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-5m\"}}}]}}}" \
	     | jq -r '.count')"; \
	   if [ "$$count" -gt 0 ]; then echo "OK   $$metric : $$count documents"; else echo "KO   $$metric : aucun document" >&2; status=1; fi; \
	 done; \
	 exit $$status

demo-api-logs-follow: ## Suivre les logs de demo-api
	@$(KUBECTL) -n $(DEMO_API_NAMESPACE) logs -f deployment/demo-api

command-center-build: ## Construire l'interface Vue.js de commandes
	@npm --prefix apps/command-center install --no-audit --no-fund
	@npm --prefix apps/command-center run build

elastic-version-validate: ## Vérifier l'alignement des versions Elastic déclarées
	@set -euo pipefail; expected='$(ELASTIC_STACK_VERSION)'; files='Makefile ansible/site.yml ansible/fleet-agent.yml ansible/roles/elk/templates ansible/roles/otel_backend/templates ansible/roles/otel_edge/templates platform/kubernetes platform/elk/dashboards'; versions="$$(find $$files -type f \( -name '*.j2' -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name 'Makefile' \) -exec grep -Eho '9\.[0-9]+\.[0-9]+' {} + || true)"; versions="$$(printf '%s\n' "$$versions" | sed -E 's/.*(9\.[0-9]+\.[0-9]+).*/\1/' | sort -u)"; \
	test "$$versions" = "$$expected" || { echo "Versions Elastic incohérentes (attendu $$expected) : $$versions" >&2; exit 1; }; \
	echo "Versions Elastic alignées sur $$expected"

images-import: ## Importer les images applicatives dans k3s
	@docker save order-service:$(APP_IMAGE_TAG) inventory-service:$(APP_IMAGE_TAG) restock-service:$(APP_IMAGE_TAG) | $(VM) shell $(K3S_VM_NAME) 'sudo /usr/local/bin/k3s ctr images import -'

k3d-ca-import: ## Faire confiance au certificat Zscaler dans les nœuds k3d (requiert ZSCALER_CA_CERT, puis redémarrer le cluster)
	@test -n "$(ZSCALER_CA_CERT)" || { echo "Définir ZSCALER_CA_CERT=chemin/vers/cert.crt" >&2; exit 1; }
	@test -f "$(ZSCALER_CA_CERT)" || { echo "Certificat Zscaler introuvable : $(ZSCALER_CA_CERT)" >&2; exit 1; }
	@nodes="$$(docker ps --filter "name=k3d-$(K3D_CLUSTER)-" --format '{{.Names}}')"; \
	test -n "$$nodes" || { echo "Aucun nœud k3d trouvé pour le cluster $(K3D_CLUSTER)" >&2; exit 1; }; \
	for node in $$nodes; do \
	  echo "→ $$node"; \
	  docker cp "$(ZSCALER_CA_CERT)" "$$node:$(K3D_CA_DEST)"; \
	  docker exec "$$node" update-ca-certificates; \
	done
	@echo "Redémarrer le cluster pour appliquer le nouveau magasin de confiance : k3d cluster stop $(K3D_CLUSTER) && k3d cluster start $(K3D_CLUSTER)"

##@ Déploiement de la plateforme Elastic

public-tls-apply: ## Créer ou réparer le certificat TLS public local du lab
	@tmp_dir="$$(mktemp -d)"; trap 'rm -rf "$$tmp_dir"' EXIT; recreate=1; \
	if $(KUBECTL) -n $(K8S_NAMESPACE) get secret elastic-public-tls >/dev/null 2>&1; then \
		$(KUBECTL) -n $(K8S_NAMESPACE) get secret elastic-public-tls -o jsonpath='{.data.tls\.crt}' | base64 --decode > "$$tmp_dir/current.crt"; \
		if openssl x509 -in "$$tmp_dir/current.crt" -noout -checkend 0 >/dev/null 2>&1 && openssl x509 -in "$$tmp_dir/current.crt" -noout -text | grep -Fq 'CA:TRUE' && openssl x509 -in "$$tmp_dir/current.crt" -noout -text | grep -Fq 'DNS:*.observability.test'; then recreate=0; echo "Secret TLS public elastic-public-tls valide"; fi; \
	fi; \
	if test "$$recreate" = 1; then \
		printf '%s\n' '[req]' 'distinguished_name = req_distinguished_name' 'x509_extensions = v3_req' 'prompt = no' '' '[req_distinguished_name]' 'CN = *.observability.test' '' '[v3_req]' 'subjectAltName = DNS:*.observability.test,DNS:observability.test' 'basicConstraints = critical,CA:TRUE' 'keyUsage = critical,digitalSignature,keyEncipherment' 'extendedKeyUsage = serverAuth' > "$$tmp_dir/openssl.cnf"; \
		openssl req -x509 -nodes -newkey rsa:2048 -days 825 -keyout "$$tmp_dir/tls.key" -out "$$tmp_dir/tls.crt" -config "$$tmp_dir/openssl.cnf" >/dev/null 2>&1; \
		$(KUBECTL) -n $(K8S_NAMESPACE) create secret tls elastic-public-tls --cert="$$tmp_dir/tls.crt" --key="$$tmp_dir/tls.key" --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
		echo "Secret TLS public elastic-public-tls créé ou réparé"; \
	fi

elasticsearch-ready:
	@password="$${ELASTIC_PASSWORD:?Set ELASTIC_PASSWORD outside Git}"; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent' >&2; exit 1; }; \
	for attempt in $$(seq 1 60); do curl --fail --silent --show-error --insecure --resolve '$(ELASTICSEARCH_CURL_RESOLVE)' -u "elastic:$$password" '$(ELASTICSEARCH_URL)' >/dev/null && exit 0; sleep 2; done; \
	echo 'Elasticsearch Quadlet inaccessible après 120s' >&2; exit 1

elasticsearch-wait: elasticsearch-ready ## Attendre qu'Elasticsearch rende son endpoint joignable

kibana-ready:
	@for attempt in $$(seq 1 60); do \
		status="$$(curl --silent --show-error --insecure \
			--resolve '$(KIBANA_CURL_RESOLVE)' -o /dev/null -w '%{http_code}' \
			'$(KIBANA_URL)/login' || true)"; \
		if test "$$status" = 200 || test "$$status" = 302 || test "$$status" = 401; then \
			echo "Ingress Kibana accessible"; exit 0; \
		fi; \
		sleep 5; \
	done; \
	echo "Ingress Kibana inaccessible après 300s" >&2; exit 1

kibana-wait: kibana-ready ## Attendre que Kibana soit prêt avant l'import de ses objets

kibana-fleet-config-deploy: elasticsearch-wait kibana-wait fleet-registry-wait ## Amorcer puis appliquer la configuration Kibana/Fleet déclarative
	@if test '$(SKIP_KUBERNETES_APPLY)' != 1; then $(MAKE) crossplane-kubernetes-apply crossplane-kubernetes-wait; fi
	@$(MAKE) kibana-ready
	@set -euo pipefail; kibana_password="$${KIBANA_PASSWORD:-$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}}"; \
	 test -n "$$kibana_password" || { echo 'Identifiant Kibana absent' >&2; exit 1; }; \
		 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" KIBANA_VERSION='$(ELASTIC_STACK_VERSION)' KUBERNETES_OTEL_PACKAGE_VERSION='$(KUBERNETES_OTEL_PACKAGE_VERSION)' KAFKA_OTEL_PACKAGE_VERSION='$(KAFKA_OTEL_PACKAGE_VERSION)' POSTGRESQL_OTEL_PACKAGE_VERSION='$(POSTGRESQL_OTEL_PACKAGE_VERSION)' MONGODB_OTEL_PACKAGE_VERSION='$(MONGODB_OTEL_PACKAGE_VERSION)' SYSTEM_OTEL_PACKAGE_VERSION='$(SYSTEM_OTEL_PACKAGE_VERSION)' OTEL_COLLECTOR_INTERNAL_TELEMETRY_PACKAGE_VERSION='$(OTEL_COLLECTOR_INTERNAL_TELEMETRY_PACKAGE_VERSION)' ./$(ARCH_ROOT)/platform/elk/scripts/bootstrap-fleet-policies.sh
	@$(MAKE) crossplane-fleet-wait
	@$(MAKE) fleet-server-start
	@$(MAKE) fleet-prerequisites

fleet-prerequisites:
	@set -euo pipefail; kibana_password="$${KIBANA_PASSWORD:-$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}}"; elasticsearch_password="$${ELASTICSEARCH_PASSWORD:-$$kibana_password}"; \
	 test -n "$$kibana_password" || { echo 'KIBANA_PASSWORD ou ELASTICSEARCH_PASSWORD requis' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' FLEET_URL='$(FLEET_URL)' FLEET_CURL_RESOLVE='$(FLEET_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ELASTICSEARCH_PASSWORD="$$elasticsearch_password" ./$(ARCH_ROOT)/platform/elk/scripts/validate-fleet-prerequisites.sh

fleet-prerequisites-validate: fleet-prerequisites ## Vérifier Elasticsearch, Kibana et Fleet Server avant les opérations Fleet

fleet-registry-ready:
	@$(VM) shell elk-01 'getent hosts epr.elastic.co >/dev/null || { echo "epr.elastic.co introuvable depuis elk-01" >&2; exit 1; }; curl --fail --silent --show-error --max-time 15 https://epr.elastic.co/ >/dev/null || { echo "Registre Fleet inaccessible depuis elk-01" >&2; exit 1; }; echo "Registre Fleet accessible"'

fleet-registry-wait: fleet-registry-ready ## Vérifier l'accès de elk-01 au registre public des packages Fleet

fleet-server-start: ## Démarrer Fleet Server après la création de sa policy et de son package
	@$(VM) shell elk-01 'sudo systemctl start observability-fleet-server.service'
	@for attempt in $$(seq 1 60); do \
		status="$$(curl --silent --show-error --insecure --resolve '$(FLEET_CURL_RESOLVE)' '$(FLEET_URL)/api/status' | jq -r '.status // empty' 2>/dev/null || true)"; \
		if test "$$status" = HEALTHY; then echo 'Fleet Server HEALTHY'; exit 0; fi; \
		sleep 5; \
	done; \
	echo 'Fleet Server non HEALTHY après 300s' >&2; exit 1

fleet-assets-deploy: ## Installer les packages et policies Fleet sans redéployer les VM ou Kubernetes
	@SKIP_KUBERNETES_APPLY=1 $(MAKE) kibana-fleet-config-deploy

elastic-stack-deploy: ## Déployer Elasticsearch, Kibana et Fleet Server sur elk-01 via Quadlet
	@password="$${ELASTIC_PASSWORD:?Set ELASTIC_PASSWORD outside Git}"; \
	api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent : définir le secret hors Git avant le déplacement.' >&2; exit 1; }; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VM) up elk-01 --no-provision
	@if test '$(SKIP_ELK_VM_PROVISION)' = 1; then \
		echo 'Provisionnement Ansible complet de elk-01 déjà effectué par deploy'; \
	else \
		password="$${ELASTIC_PASSWORD:?Set ELASTIC_PASSWORD outside Git}"; api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
		DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VM) provision elk-01; \
	fi

otel-elasticsearch-credentials-apply: ## Créer ou réconcilier la clé API Elasticsearch du Collector OTel
	@# Clé produite par Crossplane (platform/crossplane/elastic/elasticsearch.yaml).
	@$(MAKE) crossplane-elastic-wait
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' | grep -q . \
		&& echo 'Clé API otel-elasticsearch-credentials réconciliée par Crossplane'

elk-deploy: elastic-stack-deploy ## Déployer la plateforme d'observabilité Elastic sur elk-01
	@$(MAKE) elasticsearch-ready
	@# Configuration déclarative des back-ends et des objets de k3s-01 (platform/crossplane) :
	@# Secrets elasticsearch-es-elastic-user, postgresql-*-credentials et otel-edge-client-keys,
	@# manifests de la plateforme, supervision PostgreSQL et MongoDB.
	@$(MAKE) crossplane-install crossplane-credentials-apply crossplane-apply
	@$(MAKE) crossplane-secrets-wait
	@$(MAKE) public-tls-apply
	@$(MAKE) crossplane-postgresql-wait crossplane-mongodb-wait
	@$(MAKE) otel-elasticsearch-credentials-apply
	@echo "Plateforme Elastic prête ; déploiement du backend OTel puis de l'Edge"
	@$(MAKE) otel-backend-vm-provision
	@$(MAKE) otel-edge-vm-provision
	@$(MAKE) crossplane-kubernetes-wait
	@$(MAKE) crossplane-kafka-wait
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-kubernetes-cluster daemonset/otel-kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-kubernetes-cluster --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s
	@$(MAKE) kibana-ready
	@SKIP_KUBERNETES_APPLY=1 $(MAKE) kibana-fleet-config-deploy
	@$(MAKE) ilm-deploy
	@$(MAKE) apm-data-view-deploy
	@$(MAKE) observability-policies-deploy

apm-data-view-deploy: ## Importer le data view APM versionné
	@# Objets Kibana déclarés : platform/crossplane/elastic/kibana*.yaml et scripts/kibana-requests.py.
	@$(MAKE) crossplane-kibana-wait

business-dashboard-deploy: ## Importer le dashboard des métriques métier
	@# Objets Kibana déclarés : platform/crossplane/elastic/kibana*.yaml et scripts/kibana-requests.py.
	@$(MAKE) crossplane-kibana-wait

business-dashboard-replace: business-dashboard-deploy ## Supprimer puis réimporter le dashboard métier

otel-flow-dashboard-deploy: ## Déployer le dashboard de santé des flux OTel
	@# Objets Kibana déclarés : platform/crossplane/elastic/kibana*.yaml et scripts/kibana-requests.py.
	@$(MAKE) crossplane-kibana-wait

observability-policies-validate: ## Vérifier le manifeste versionné des alertes (et des SLO, non déployés)
	@jq -e '(.slos | type == "array" and length > 0) and (.rules | type == "array" and length > 0) and ([.slos[].id, .rules[].id] | all(type == "string" and length > 0)) and ([.slos[] | select(.indicator.type == "sli.metric.timeslice") | ((.budgetingMethod == "timeslices") and (.objective.target > 0 and .objective.target < 1) and (.objective.timesliceTarget > 0 and .objective.timesliceTarget < 1) and (.objective.timesliceWindow | type == "string" and length > 0) and (.indicator.params.metric.metrics | type == "array" and length > 0))] | all) and ([.rules[].body | select(.rule_type_id == ".es-query" and .params.searchType == "esQuery") | .params.esQuery | fromjson] | all(type == "object")) and ([.rules[].body | select(.rule_type_id == ".es-query" and .params.searchType == "esqlQuery") | .params.esqlQuery.esql] | all(type == "string" and length > 0))' $(ARCH_ROOT)/platform/elk/alerts/observability-policies.json >/dev/null
	@bash -n $(ARCH_ROOT)/platform/elk/scripts/sync-observability-policies.sh

observability-policies-deploy: observability-policies-validate ## Réconcilier les règles d’alerte de l’architecture dans Kibana
	@# Objets Kibana déclarés : platform/crossplane/elastic/kibana*.yaml et scripts/kibana-requests.py.
	@$(MAKE) crossplane-kibana-wait

apm-kibana-role-apply: ## Accorder au compte APM les droits Kibana APM/Fleet en lecture
	@elasticsearch_password="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' | base64 --decode )"; \
	test -n "$$elasticsearch_password" || { echo "Impossible de lire le mot de passe Elasticsearch" >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' \
		ELASTICSEARCH_PASSWORD="$$elasticsearch_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/apply-apm-kibana-role.sh

##@ Déploiement et recette de l'application

apps-deploy: ## Déployer uniquement l'application de démonstration
	@test '$(DEPLOYMENT_PROFILE)' = minimal || { echo "Profil Kubernetes inconnu : $(DEPLOYMENT_PROFILE) (seul minimal est supporté)" >&2; exit 1; }
	@$(MAKE) crossplane-secrets-wait
	@# Application Crossplane (platform/crossplane/applications), tag fixé par APP_IMAGE_TAG.
	@$(call CROSSPLANE_APPLY_PRUNE,$(CROSSPLANE_APPLICATIONS) $(APP_MANIFEST_ROOT)/application.yaml,applications.apps.lab.io,applications)
	@$(KUBECTL) -n $(APP_NAMESPACE) wait --for=condition=Ready applications.apps.lab.io --all --timeout=$(CROSSPLANE_TIMEOUT)
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/order-service --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/inventory-service --timeout=180s
	@$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/restock-service --timeout=180s

apps-restart: ## Redémarrer les services supermarket-demo pour recharger la configuration de l'agent OTel (ConfigMap sans suffixe de hash)
	@for deployment in order-service inventory-service restock-service; do \
	  $(KUBECTL) -n $(APP_NAMESPACE) rollout restart deployment/$$deployment; \
	done
	@for deployment in order-service inventory-service restock-service; do \
	  $(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/$$deployment --timeout=240s; \
	done

application-data-verify: ## Vérifier le schéma et le catalogue avant une charge de test
	@set -euo pipefail; \
	$(KUBECTL) -n $(APP_NAMESPACE) rollout status deployment/order-service --timeout=180s; \
	count="$$( $(VM) shell supermarket-middleware-01 'sudo podman exec observability-postgresql psql -U observability -d observability_test -tAc "SELECT count(*) FROM public.products;"' | tr -d '[:space:]' )"; \
	test "$$count" -ge 1 || { echo 'Le catalogue PostgreSQL est absent ou vide : exécuter les migrations et le chargement des produits.' >&2; exit 1; }; \
	echo "Catalogue applicatif prêt ($$count produits)"

order-service-command: application-data-verify ## Envoyer une commande REST (ORDER_PRODUCT_ID, ORDER_QUANTITY) à order-service
	@pod_name="order-service-command-$$(date +%s)"; \
	$(KUBECTL) -n $(APP_NAMESPACE) run "$$pod_name" --image=curlimages/curl:8.12.1 \
		--restart=Never --rm --attach -i --command -- \
		curl --fail --silent --show-error -X POST http://order-service:3000/api/orders \
		-H 'Content-Type: application/json' \
		--data '{"productId":"$(ORDER_PRODUCT_ID)","quantity":$(ORDER_QUANTITY)}'

##@ Déploiement complet et validation

slides:
	@npm --prefix slides run dev

slides-start: slides ## Démarrer le support Slidev de l'architecture

vms-up:
	@set -euo pipefail; \
	test -r '$(OBSERVABILITY_CREDENTIALS_FILE)' || { echo "Fichier d’identifiants introuvable : $(OBSERVABILITY_CREDENTIALS_FILE). Exécuter source ./platform/elk/scripts/generate-otel-edge-keys.sh." >&2; exit 1; }; \
	source '$(OBSERVABILITY_CREDENTIALS_FILE)'; \
	for key in $(OTEL_EDGE_KEYS); do test -n "$${!key:-}" || { echo "Clé Edge absente : $$key." >&2; exit 1; }; done; \
	postgresql_password="$${POSTGRESQL_PASSWORD:?Set POSTGRESQL_PASSWORD outside Git}"; \
	mongodb_password="$${MONGODB_PASSWORD:?Set MONGODB_PASSWORD outside Git}"; \
	kafka_otel_publisher_password="$${KAFKA_OTEL_PUBLISHER_PASSWORD:?Set KAFKA_OTEL_PUBLISHER_PASSWORD outside Git}"; \
	kafka_otel_consumer_password="$${KAFKA_OTEL_CONSUMER_PASSWORD:?Set KAFKA_OTEL_CONSUMER_PASSWORD outside Git}"; \
	zscaler_ca_cert_content=''; \
	if test -n "$${ZSCALER_CA_CERT:-}"; then test -f "$$ZSCALER_CA_CERT" || { echo "Certificat Zscaler introuvable : $$ZSCALER_CA_CERT" >&2; exit 1; }; zscaler_ca_cert_content="$$(< "$$ZSCALER_CA_CERT")"; fi; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$$postgresql_password" MONGODB_PASSWORD="$$mongodb_password" KAFKA_OTEL_PUBLISHER_PASSWORD="$$kafka_otel_publisher_password" KAFKA_OTEL_CONSUMER_PASSWORD="$$kafka_otel_consumer_password" ELASTIC_PASSWORD="$${ELASTIC_PASSWORD:?Set ELASTIC_PASSWORD outside Git}" $(VM) up --parallel supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 $(K3S_VM_NAME) --no-provision; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$$postgresql_password" MONGODB_PASSWORD="$$mongodb_password" KAFKA_OTEL_PUBLISHER_PASSWORD="$$kafka_otel_publisher_password" KAFKA_OTEL_CONSUMER_PASSWORD="$$kafka_otel_consumer_password" ELASTIC_PASSWORD="$${ELASTIC_PASSWORD:?Set ELASTIC_PASSWORD outside Git}" ZSCALER_CA_CERT_CONTENT="$$zscaler_ca_cert_content" ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i $(ARCH_ROOT)/ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/site.yml

vms-start: vms-up ## Démarrer et provisionner les cinq VM, sans déployer Kubernetes ni l'application

vms-restart: ## Redémarrer les cinq VM sans reprovisionnement Ansible
	@./scripts/vms-restart.sh

metrics-chain-restart: ## Redémarrer les gateways et le Kafka de la chaîne métriques
	@./scripts/metrics-chain-restart.sh

k3s-vm-up: ## Créer et provisionner la VM serveur k3s
	@set -euo pipefail; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' $(VM) up $(K3S_VM_NAME) --no-provision; \
	ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i $(ARCH_ROOT)/ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/site.yml --limit $(K3S_VM_NAME)

k3s-kubeconfig: ## Exporter le kubeconfig k3s vers un fichier local non versionné
	@K3S_KUBECONFIG='$(K3S_KUBECONFIG)' ./scripts/k3s-kubeconfig.sh

vms-destroy: ## Détruire les cinq VM Lima et leurs disques locaux (DESTRUCTIF)
	@$(VM) delete supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 $(K3S_VM_NAME)

# VM dont l'agent EDOT est provisionné ; restreindre avec
# make elastic-agent-vm-provision ELASTIC_AGENT_VMS="elk-01".
ELASTIC_AGENT_VMS ?= $(K3S_VM_NAME) supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01

elastic-agent-vm-provision: ## Déployer la configuration EDOT standalone des agents VM (ELASTIC_AGENT_VMS)
	@set -euo pipefail; \
	test -r '$(OBSERVABILITY_CREDENTIALS_FILE)' || { echo "Fichier d’identifiants introuvable : $(OBSERVABILITY_CREDENTIALS_FILE). Exécuter source ./platform/elk/scripts/generate-otel-edge-keys.sh." >&2; exit 1; }; \
	source '$(OBSERVABILITY_CREDENTIALS_FILE)'; \
	for key in $(OTEL_EDGE_KEYS); do test -n "$${!key:-}" || { echo "Clé Edge absente : $$key." >&2; exit 1; }; done; \
	api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	test -n "$$api_key" || { echo 'Clé API OTel absente : exécuter d’abord make otel-elasticsearch-credentials-apply.' >&2; exit 1; }; \
	for node in $(ELASTIC_AGENT_VMS); do \
	  echo "Provisionnement Elastic Agent EDOT : $$node"; \
	  OTEL_ELASTICSEARCH_API_KEY="$$api_key" DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:?Set POSTGRESQL_PASSWORD outside Git}" MONGODB_PASSWORD="$${MONGODB_PASSWORD:?Set MONGODB_PASSWORD outside Git}" $(VM) provision "$$node"; \
	done

elastic-agent-backend-provision: ## Déployer uniquement la configuration EDOT du backend
	@api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	test -n "$$api_key" || { echo 'Clé API OTel absente : exécuter d’abord make otel-elasticsearch-credentials-apply.' >&2; exit 1; }; \
	OTEL_ELASTICSEARCH_API_KEY="$$api_key" DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:?Set POSTGRESQL_PASSWORD outside Git}" MONGODB_PASSWORD="$${MONGODB_PASSWORD:?Set MONGODB_PASSWORD outside Git}" $(VM) provision otel-backend-01

middleware-vm-provision: ## Reprovisionner le middleware et sa route vers le réseau des pods
	@set -euo pipefail; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:?Set POSTGRESQL_PASSWORD outside Git}" MONGODB_PASSWORD="$${MONGODB_PASSWORD:?Set MONGODB_PASSWORD outside Git}" $(VM) provision supermarket-middleware-01

k3s-vm-provision: ## Reprovisionner k3s et le forwarding du réseau des pods
	@DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' $(VM) provision $(K3S_VM_NAME)

deploy:
	@set -euo pipefail; \
	password="$$( $(VM) shell elk-01 'sudo cat /etc/observability/elasticsearch.env' | sed -n 's/^ELASTIC_PASSWORD=//p' | head -n 1 | tr -d '\r' )"; \
	test -n "$$password" || { echo 'Mot de passe Elasticsearch introuvable sur elk-01.' >&2; exit 1; }; \
	export ELASTIC_PASSWORD="$$password"; \
	$(MAKE) k3s-kubeconfig; \
	SKIP_ELK_VM_PROVISION=1 $(MAKE) elk-deploy; \
	$(MAKE) apps-build; \
	$(MAKE) images-import; \
	$(MAKE) apps-deploy; \
	$(MAKE) demo-api-build; \
	$(MAKE) demo-api-import; \
	$(MAKE) demo-api-deploy; \
	$(MAKE) deploy-post

architecture-deploy: deploy ## Déployer Elastic, Fleet, Kubernetes et les applications

deploy-post:
	@set -euo pipefail; \
	$(MAKE) otel-backend-vm-provision; \
	$(MAKE) fleet-opamp-enable; \
	$(MAKE) cache-save-k3s-images

deployment-finalize: deploy-post ## Finaliser les services VM et le monitoring OpAMP

kubernetes-validate: ## Générer les manifests Kustomize sans les appliquer
	@$(KUBECTL) kustomize $(ARCH_ROOT)/platform/kubernetes/overlays/local >/dev/null
	@KUBECTL='$(KUBECTL)' python3 $(CROSSPLANE_ROOT)/scripts/kubernetes-objects.py $(ARCH_ROOT)/platform/kubernetes/overlays/local >/dev/null
	@$(CROSSPLANE_APPLICATIONS) $(APP_MANIFEST_ROOT)/application.yaml $(DEMO_API_MANIFEST_ROOT)/application.yaml >/dev/null

ansible-validate: ## Vérifier la syntaxe du playbook Ansible sans provisionner
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/site.yml
	@# --syntax-check ne charge pas les tâches des rôles : --list-tasks détecte aussi leurs erreurs d'analyse.
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --list-tasks -i ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/site.yml >/dev/null
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/render-otel-configs.yml

OTEL_RENDER_DIR ?= $(ARCH_ROOT)/.otel-render
OTEL_COLLECTOR_IMAGE ?= docker.elastic.co/elastic-agent/elastic-otel-collector:$(ELASTIC_STACK_VERSION)

otel-config-validate: ## Rendre les configurations Edge, backend et agents depuis l'inventaire et les valider avec EDOT
	@set -euo pipefail; \
	rm -rf '$(OTEL_RENDER_DIR)'; \
	OTEL_RENDER_DIR='$(abspath $(OTEL_RENDER_DIR))' ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/render-otel-configs.yml >/dev/null; \
	for file in '$(OTEL_RENDER_DIR)'/elastic-agent-*.yaml; do sed '1,/^$$/d' "$$file" > "$${file%.yaml}.collector.yaml"; done; \
	for file in '$(OTEL_RENDER_DIR)'/otel-edge-*.yaml '$(OTEL_RENDER_DIR)'/otel-backend-*.yaml '$(OTEL_RENDER_DIR)'/elastic-agent-*.collector.yaml; do \
	  docker run --rm --tmpfs /var/lib/otel-edge --tmpfs /var/lib/otel \
	    -e OTEL_KAFKA_PUBLISHER_USERNAME=render -e OTEL_KAFKA_PUBLISHER_PASSWORD=render \
	    -e OTEL_KAFKA_CONSUMER_USERNAME=render -e OTEL_KAFKA_CONSUMER_PASSWORD=render \
	    -e ELASTICSEARCH_API_KEY=render \
	    -v "$(abspath $(OTEL_RENDER_DIR)):/render:ro" '$(OTEL_COLLECTOR_IMAGE)' validate --config="/render/$$(basename "$$file")"; \
	  echo "OK      $$(basename "$$file")"; \
	done; \
	echo "Topics attendus : $$(tr '\n' ' ' < '$(OTEL_RENDER_DIR)/otel-topics.txt')"

otel-validation:
	@test -r '$(OBSERVABILITY_CREDENTIALS_FILE)' || { echo "Fichier d’identifiants introuvable : $(OBSERVABILITY_CREDENTIALS_FILE). Exécuter source ./platform/elk/scripts/generate-otel-edge-keys.sh." >&2; exit 1; }; \
	source '$(OBSERVABILITY_CREDENTIALS_FILE)'; \
	export ELASTICSEARCH_PASSWORD="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	inventory="$${INVENTORY:-$(VALIDATION_ROOT)/inventory/hosts.yml}"; \
	validation_tags="$${VALIDATION_TAGS:-}"; \
	case "$$inventory" in /*|../*) ;; *) inventory="../$$inventory";; esac; \
	if [ -z "$${INVENTORY:-}" ]; then \
	  ssh_port="$$( $(VM) ssh-config otel-edge-01 | awk '$$1 == "Port" {print $$2; exit}' )"; \
	  ssh_key="$$( $(VM) ssh-config otel-edge-01 | awk '$$1 == "IdentityFile" {print $$2; exit}' )"; \
	  test -n "$$ssh_port" || { echo 'Port SSH Lima introuvable pour otel-edge-01.' >&2; exit 1; }; \
	  test -f "$$ssh_key" || { echo 'Clé SSH Lima introuvable pour otel-edge-01.' >&2; exit 1; }; \
	  inventory_tmp="$$(mktemp /tmp/otel-validation-inventory.XXXXXX.yml)"; \
	  trap 'rm -f "$$inventory_tmp"' EXIT; \
	  sed -e "s/ansible_port: 22/ansible_port: $$ssh_port/" -e "s#ansible_ssh_private_key_file:.*#ansible_ssh_private_key_file: $$ssh_key#" "$$inventory" > "$$inventory_tmp"; \
	  inventory="$$inventory_tmp"; \
	fi; \
	if [ -n "$$validation_tags" ]; then tag_args=(--tags "$$validation_tags"); else tag_args=(); fi; \
	ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook "$${tag_args[@]}" -i "$$inventory" $(VALIDATION_ROOT)/playbook.yml

otel-validate: otel-validation ## Valider OTLP (VALIDATION_TAGS=host|direct ; vide = les deux)

ci: kubernetes-validate ansible-validate elastic-version-validate apps-test

ci-run: ci ## Exécuter les validations reproductibles du dépôt

##@ Provisionnement des VM et Fleet

fleet-sync: ## Synchroniser les pipelines et la policy Fleet
	@# Pipelines @custom déclarés dans platform/crossplane/elastic/elasticsearch.yaml.
	@$(MAKE) crossplane-elastic-wait

mongodb-workload:
	@$(VM) shell supermarket-middleware-01 'sudo podman exec -i observability-mongodb mongosh --quiet' < $(SHARED_SCRIPTS_ROOT)/mongodb-elk-workload.js

mongodb-workload-generate: mongodb-workload ## Générer une charge MongoDB courte pour valider la collecte

fleet-opamp-enable: fleet-assets-deploy ## Activer le monitoring Fleet OpAMP des agents EDOT des VM sans redéployer la plateforme
	@set -euo pipefail; kibana_password="$${KIBANA_PASSWORD:-$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}}"; \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/provision-fleet-vms.sh

otel-edge-vm-provision: ## Provisionner le Collecteur EDOT Edge sur otel-edge-01
	@set -euo pipefail; \
	test -r '$(OBSERVABILITY_CREDENTIALS_FILE)' || { echo "Fichier d’identifiants introuvable : $(OBSERVABILITY_CREDENTIALS_FILE). Exécuter source ./platform/elk/scripts/generate-otel-edge-keys.sh." >&2; exit 1; }; \
	source '$(OBSERVABILITY_CREDENTIALS_FILE)'; \
	for key in $(OTEL_EDGE_KEYS); do test -n "$${!key:-}" || { echo "Clé Edge absente : $$key." >&2; exit 1; }; done; \
	$(VM) up otel-edge-01 --no-provision; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' POSTGRESQL_PASSWORD="$${POSTGRESQL_PASSWORD:?Set POSTGRESQL_PASSWORD outside Git}" KAFKA_OTEL_PUBLISHER_PASSWORD="$${KAFKA_OTEL_PUBLISHER_PASSWORD:?Set KAFKA_OTEL_PUBLISHER_PASSWORD outside Git}" KAFKA_OTEL_CONSUMER_PASSWORD="$${KAFKA_OTEL_CONSUMER_PASSWORD:?Set KAFKA_OTEL_CONSUMER_PASSWORD outside Git}" $(VM) provision otel-edge-01

otel-gateway-vm-status: ## Vérifier HAProxy, le Collecteur EDOT Edge et le backend OTel
	@set -euo pipefail; $(VM) shell otel-edge-01 'sudo systemctl is-active haproxy && sudo systemctl is-active observability-otel-edge && curl --fail --silent http://127.0.0.1:13135/'; $(VM) shell otel-backend-01 'sudo systemctl is-active observability-otel-backend && curl --fail --silent http://127.0.0.1:13134/'

kubernetes-observability-deploy: crossplane-secrets-wait ## Appliquer et vérifier les Collectors Kubernetes déclarés par Kustomize
	@$(MAKE) crossplane-kubernetes-apply crossplane-kubernetes-wait
	@$(MAKE) crossplane-kafka-wait
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout restart deployment/otel-kubernetes-cluster daemonset/otel-kubernetes
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status deployment/otel-kubernetes-cluster --timeout=180s
	@$(KUBECTL) -n $(K8S_NAMESPACE) rollout status daemonset/otel-kubernetes --timeout=180s

otel-backend-vm-provision: ## Provisionner le collecteur backend OTel sur otel-backend-01 avec la clé API Kubernetes existante
	@$(VM) up otel-backend-01 --no-provision
	@api_key="$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret otel-elasticsearch-credentials -o jsonpath='{.data.api-key}' 2>/dev/null | base64 --decode )"; \
	password="$${ELASTIC_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	publisher_password="$${KAFKA_OTEL_PUBLISHER_PASSWORD:?Set KAFKA_OTEL_PUBLISHER_PASSWORD outside Git}"; \
	consumer_password="$${KAFKA_OTEL_CONSUMER_PASSWORD:?Set KAFKA_OTEL_CONSUMER_PASSWORD outside Git}"; \
	test -n "$$api_key" || { echo 'Clé API OTel absente : exécuter d’abord make otel-elasticsearch-credentials-apply.' >&2; exit 1; }; \
	test -n "$$password" || { echo 'ELASTIC_PASSWORD absent.' >&2; exit 1; }; \
	DEPLOYMENT_PROFILE='$(DEPLOYMENT_PROFILE)' ELASTIC_PASSWORD="$$password" KAFKA_OTEL_PUBLISHER_PASSWORD="$$publisher_password" KAFKA_OTEL_CONSUMER_PASSWORD="$$consumer_password" OTEL_ELASTICSEARCH_API_KEY="$$api_key" $(VM) provision otel-backend-01
otel-backend-vm-status: ## Vérifier le collecteur backend OTel exécuté sur otel-backend-01
	@$(VM) shell otel-backend-01 'sudo systemctl is-active observability-otel-backend && curl --fail --silent http://127.0.0.1:13134/'

##@ Dashboards et consultation

dashboards-verify: ## Vérifier que les jeux de données alimentant les dashboards sont récents
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
		test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la stack Elastic Quadlet.' >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-dashboard-data.sh

postgresql-otel-dashboards-verify: ## Vérifier les métriques et requêtes des dashboards PostgreSQL OTel
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
		test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" \
	KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$es_password" \
		./$(ARCH_ROOT)/platform/elk/scripts/verify-postgresql-otel-dashboards.sh

kubernetes-otel-dashboards-verify: ## Vérifier les requêtes des dashboards Kubernetes OTel
	@kibana_password="$${KIBANA_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$kibana_password" || { echo 'KIBANA_PASSWORD ou le secret ECK est requis' >&2; exit 1; }; \
	 KIBANA_URL='$(KIBANA_URL)' KIBANA_CURL_RESOLVE='$(KIBANA_CURL_RESOLVE)' KIBANA_PASSWORD="$$kibana_password" ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ./$(ARCH_ROOT)/platform/elk/scripts/verify-kubernetes-otel-dashboards.sh

trace-context-verify: ## Vérifier la propagation W3C jusqu’à Kafka et les logs corrélés
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	 ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" ./$(ARCH_ROOT)/platform/elk/scripts/verify-observability-contracts.sh trace-context

observability-schema-verify: ## Vérifier le contrat OTel des événements indexés (logs et métriques OTel natifs)
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	 ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" ./$(ARCH_ROOT)/platform/elk/scripts/verify-observability-contracts.sh schema

# Plateformes lues dans l'inventaire (otel_platforms, group_vars/all.yml, ADR-015).
OTEL_PLATFORMS ?= $(shell python3 -c 'import re,sys; print(" ".join(sorted(set(re.findall(r"^  platform: (\S+)", open(sys.argv[1]).read(), re.M)))))' $(ARCH_ROOT)/platform/crossplane/platforms.yaml)

otel-kafka-acl-verify: ## Vérifier que chaque producteur n'écrit que dans les topics Kafka OTel de ses plateformes (ADR-017)
	@set -euo pipefail; \
	test -r '$(OBSERVABILITY_CREDENTIALS_FILE)' && source '$(OBSERVABILITY_CREDENTIALS_FILE)'; \
	KAFKA_OTEL_PUBLISHER_PASSWORD="$${KAFKA_OTEL_PUBLISHER_PASSWORD:?Set KAFKA_OTEL_PUBLISHER_PASSWORD outside Git}" \
	ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/lima.yml $(ARCH_ROOT)/ansible/otel-kafka-acl-verify.yml

otel-routing-verify: ## Vérifier le routage par plateforme (platform.id, namespaces, rejets de l'Edge) sur les documents récents
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour la vérification.' >&2; exit 1; }; \
	 test -n "$(OTEL_PLATFORMS)" || { echo 'OTEL_PLATFORMS introuvable dans l’inventaire.' >&2; exit 1; }; \
	 ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" OTEL_PLATFORMS='$(OTEL_PLATFORMS)' ./$(ARCH_ROOT)/platform/elk/scripts/verify-otel-routing.sh

otel-legacy-datastreams-delete: ## Lister (CONFIRM=1 : supprimer) les data streams OTel sans plateforme inactifs depuis LEGACY_INACTIVE_WINDOW (ADR-019)
	@set -euo pipefail; es_password="$${ELASTICSEARCH_PASSWORD:-$$( $(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null | base64 --decode )}"; \
	 test -n "$$es_password" || { echo 'ELASTICSEARCH_PASSWORD requis pour le nettoyage.' >&2; exit 1; }; \
	 ELASTICSEARCH_URL='$(ELASTICSEARCH_URL)' ELASTICSEARCH_CURL_RESOLVE='$(ELASTICSEARCH_CURL_RESOLVE)' ELASTICSEARCH_PASSWORD="$$es_password" CONFIRM='$(CONFIRM)' LEGACY_INACTIVE_WINDOW='$(LEGACY_INACTIVE_WINDOW)' ./$(ARCH_ROOT)/platform/elk/scripts/delete-legacy-otel-datastreams.sh

##@ Identifiants et clés d'accès

apm-report-api-key-create: ## Créer une clé de lecture brute pour les rapports APM SystemLens
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (source $(ARCH_ROOT)/platform/elk/scripts/load-credentials.sh)" >&2; exit 1; }
	@curl --fail --silent --show-error --insecure \
		--resolve '$(ELASTICSEARCH_CURL_RESOLVE)' \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data "{\"name\":\"systemlens-apm-report-$$(date +%Y%m%d%H%M%S)\",\"role_descriptors\":{\"systemlens_apm_report_reader\":{\"cluster\":[\"monitor\"],\"indices\":[{\"names\":[\"traces-*\",\"metrics-*\"],\"privileges\":[\"read\",\"view_index_metadata\"]}]}}}" \
		| jq -er '.id + ":" + .api_key'

elastic-password-show: ## Afficher le mot de passe du compte elastic ECK
	@$(KUBECTL) -n $(K8S_NAMESPACE) get secret elasticsearch-es-elastic-user \
		-o go-template='{{.data.elastic | base64decode}}{{"\\n"}}'

kibana-password-show: elastic-password-show ## Afficher le mot de passe Kibana (compte elastic)

elasticsearch-api-key-create: ## Créer une clé API Base64 pour les rapports APM SystemLens
	@test -n "$$ELASTICSEARCH_PASSWORD" || { echo "Définir ELASTICSEARCH_PASSWORD (make elastic-password-show)" >&2; exit 1; }
	@api_key="$$(curl --fail --silent --show-error --insecure \
		-u "elastic:$$ELASTICSEARCH_PASSWORD" \
		-H 'Content-Type: application/json' \
		-X POST '$(ELASTICSEARCH_URL)/_security/api_key' \
		--data '{"name":"vm-beats-$$(date +%Y%m%d%H%M%S)","role_descriptors":{"vm_beats_writer":{"cluster":["monitor","read_ilm","manage_ilm","manage_index_templates"],"indices":[{"names":["logs-*","metrics-*","filebeat-*","metricbeat-*"],"privileges":["auto_configure","create_doc","read","view_index_metadata"]},{"names":["traces-*"],"privileges":["read","view_index_metadata"]}]}}}' \
		| jq -er '.id + ":" + .api_key')"; \
	printf '%s' "$$api_key" | base64 | tr -d '\n'; echo

##@ Consultation locale

stock-view:
	@$(VM) shell supermarket-middleware-01 'sudo podman exec observability-postgresql psql -U observability -d observability_test -P pager=off -c "SELECT id, name, stock_quantity AS stock FROM products ORDER BY id;"'

stock-show: stock-view ## Afficher le stock courant du catalogue PostgreSQL

order-service-logs-follow: ## Suivre les logs de order-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/order-service

inventory-service-logs-follow: ## Suivre les logs de inventory-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/inventory-service

restock-service-logs-follow: ## Suivre les logs de restock-service
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -f deployment/restock-service

##@ Cache local des téléchargements

# Répertoire de l'hôte monté par Lima sur /var/cache/lab dans les 5 VM (lima/base.yaml, même chemin).
# Il survit à make vms-destroy : fichiers, paquets .deb, images Podman, images de k3s-01, providers
# Terraform et paquets Crossplane y sont lus avant tout téléchargement.
CACHE_DIR := $(HOME)/.cache/poc-crossplane-lab

cache-status: ## Afficher le contenu du cache local et son montage dans les VM
	@mkdir -p '$(CACHE_DIR)'
	@echo "Cache local : $(CACHE_DIR)"
	@du -sh '$(CACHE_DIR)' 2>/dev/null | awk '{print "Total : " $$1}'
	@for d in files apt podman k3s terraform-plugins crossplane-packages; do \
	  test -d '$(CACHE_DIR)'/$$d && printf '  %-20s %6s  %s fichier(s)\n' "$$d" "$$(du -sh '$(CACHE_DIR)'/$$d | cut -f1)" "$$(find '$(CACHE_DIR)'/$$d -type f | wc -l | tr -d ' ')"; \
	done; true
	@for node in supermarket-middleware-01 otel-backend-01 otel-edge-01 elk-01 $(K3S_VM_NAME); do \
	  state="$$($(VM) state "$$node")"; \
	  if test "$$state" = Running; then \
	    $(VM) shell "$$node" 'mountpoint -q /var/cache/lab && echo monté || echo "non monté"' | sed "s/^/  $$node : /"; \
	  else echo "  $$node : $$state"; fi; \
	done

cache-clean: ## Vider le cache local (le prochain déploiement retélécharge tout)
	@case '$(CACHE_DIR)' in */.cache/poc-crossplane-lab) ;; *) echo 'CACHE_DIR inattendu : $(CACHE_DIR)' >&2; exit 1;; esac
	@mkdir -p '$(CACHE_DIR)' && find '$(CACHE_DIR)' -mindepth 1 -delete && echo 'Cache local vidé : $(CACHE_DIR)'

cache-save-k3s-images: ## Sauvegarder dans le cache local les images de k3s-01 (après un déploiement réussi)
	@$(VM) shell $(K3S_VM_NAME) 'sudo bash -s' < $(ARCH_ROOT)/scripts/cache-save-k3s-images.sh

##@ Rétention et cycle de vie

.PHONY: retention-validate retention-plan retention-deploy retention-verify ilm-deploy

retention-validate: ## Valider les règles de rétention sans les appliquer
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/lima.yml ansible/retention.yml
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook --syntax-check -i ansible/inventory/lima.yml ansible/retention-verify.yml
	@python3 -c 'import ast,json,pathlib; ast.parse(pathlib.Path("platform/elk/scripts/retention.py").read_text()); ast.parse(pathlib.Path("ansible/roles/retention/files/purge-logs.py").read_text()); json.loads(pathlib.Path("platform/elk/ilm/retention.json").read_text())'

retention-plan: ## Lire le périmètre et les politiques ILM sans mutation
	@python3 platform/elk/scripts/retention.py plan

ilm-deploy: ## Réconcilier les politiques ILM et les indices existants
	@python3 platform/elk/scripts/retention.py apply

retention-deploy: retention-validate ## Déployer uniquement la rétention VM, Kafka et ILM
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/lima.yml ansible/retention.yml
	@$(MAKE) ilm-deploy
	@$(MAKE) retention-verify

retention-verify: ## Contrôler les timers, Kafka et ILM effectivement déployés
	@ANSIBLE_LOCAL_TEMP=/tmp ansible-playbook -i ansible/inventory/lima.yml ansible/retention-verify.yml
	@python3 platform/elk/scripts/retention.py verify

# ---------------------------------------------------------------------------
# Crossplane : configuration déclarative des back-ends (platform/crossplane)
# ---------------------------------------------------------------------------
CROSSPLANE_ROOT := $(ARCH_ROOT)/platform/crossplane
CROSSPLANE_VERSION ?= 2.4.3
CROSSPLANE_TIMEOUT ?= 15m
# Application Crossplane des services, avec la configuration de l'agent OTel et le tag d'image.
CROSSPLANE_APPLICATIONS = python3 $(CROSSPLANE_ROOT)/scripts/applications.py \
	--tag order-service=$(APP_IMAGE_TAG) --tag inventory-service=$(APP_IMAGE_TAG) --tag restock-service=$(APP_IMAGE_TAG) \
	--tag demo-api=$(DEMO_API_IMAGE_TAG)
# Applique un rendu Crossplane puis élague (scripts/prune.py) les ressources du même label absentes
# du rendu : $(call CROSSPLANE_APPLY_PRUNE,<commande de rendu>,<ressource>,<valeur de lab.io/managed-by>)
CROSSPLANE_APPLY_PRUNE = tmp="$$(mktemp)"; trap 'rm -f "$$tmp"' EXIT; \
	$(1) > "$$tmp" && $(KUBECTL) apply -f "$$tmp" && \
	KUBECTL='$(KUBECTL)' python3 $(CROSSPLANE_ROOT)/scripts/prune.py $(2) $(3) "$$tmp"

crossplane-install: ## Installer Crossplane, ses providers et ses fonctions dans k3s-01
	@$(KUBECTL) create namespace crossplane-system --dry-run=client -o yaml | $(KUBECTL) apply -f -
	@# Bundle CA de k3s-01 (inclut la racine du proxy TLS d'entreprise installée par Ansible)
	@$(VM) shell $(K3S_VM_NAME) 'cat /etc/ssl/certs/ca-certificates.crt' > $(ARCH_ROOT)/.kube/ca-certificates.crt
	@$(KUBECTL) -n crossplane-system create configmap ca-bundle --from-file=ca-certificates.crt=$(ARCH_ROOT)/.kube/ca-certificates.crt \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	@# Cache des paquets Crossplane dans le cache local de l'hôte (install/package-cache.yaml).
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/install/package-cache.yaml
	@# Configuration Helm isolée : indépendante des dépôts configurés sur le poste.
	@HELM_REPOSITORY_CONFIG=$(ARCH_ROOT)/.kube/helm/repositories.yaml HELM_REPOSITORY_CACHE=$(ARCH_ROOT)/.kube/helm/cache \
		helm upgrade --install crossplane crossplane --repo https://charts.crossplane.io/stable --version $(CROSSPLANE_VERSION) \
		-n crossplane-system --set registryCaBundleConfig.name=ca-bundle --set registryCaBundleConfig.key=ca-certificates.crt \
		--set packageCache.pvc=crossplane-package-cache \
		--wait --timeout 10m
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/install/
	@$(KUBECTL) wait --for=condition=Healthy providers.pkg.crossplane.io --all --timeout=$(CROSSPLANE_TIMEOUT)
	@$(KUBECTL) wait --for=condition=Healthy functions.pkg.crossplane.io --all --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-credentials-apply: ## Déposer les Secrets d'accès des providers (depuis .observability-credentials.env)
	@set -euo pipefail; source '$(OBSERVABILITY_CREDENTIALS_FILE)'; KUBECTL='$(KUBECTL)' $(CROSSPLANE_ROOT)/scripts/credentials.sh

crossplane-apply: ## Appliquer toute la configuration Crossplane (Kafka, PostgreSQL, MongoDB, Elastic, Kibana, Kubernetes)
	@$(KUBECTL) apply -f $(ARCH_ROOT)/platform/kubernetes/base/observability/namespace.yaml
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/config/
	@KUBECTL='$(KUBECTL)' $(CROSSPLANE_ROOT)/scripts/assets.sh
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/kafka-otel/definition.yaml
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/applications/definition.yaml
	@$(KUBECTL) wait --for=condition=Established xrd/otelplatforms.observability.lab.io xrd/applications.apps.lab.io --timeout=180s
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/kafka-otel/ -f $(CROSSPLANE_ROOT)/platforms.yaml -f $(CROSSPLANE_ROOT)/applications/
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/kafka-business/ -f $(CROSSPLANE_ROOT)/postgresql/ -f $(CROSSPLANE_ROOT)/mongodb/ -f $(CROSSPLANE_ROOT)/elastic/
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/kubernetes/
	@python3 $(CROSSPLANE_ROOT)/scripts/kibana-requests.py | $(KUBECTL) apply -f -
	@$(MAKE) crossplane-kubernetes-apply

crossplane-kubernetes-apply: ## Réconcilier les manifests Kustomize de la plateforme sous forme d'Object Crossplane
	@$(call CROSSPLANE_APPLY_PRUNE,KUBECTL='$(KUBECTL)' python3 $(CROSSPLANE_ROOT)/scripts/kubernetes-objects.py $(ARCH_ROOT)/platform/kubernetes/overlays/local,objects.kubernetes.m.crossplane.io,kubernetes-objects)

crossplane-kubernetes-wait: ## Attendre les objets de la plateforme Kubernetes (namespace, Services, collecteurs, RBAC)
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready objects.kubernetes.m.crossplane.io -l lab.io/managed-by=kubernetes-objects --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-secrets-wait: ## Attendre les namespaces applicatifs et les Secrets des workloads
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready objects.kubernetes.m.crossplane.io -l lab.io/managed-by=kubernetes-secrets --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-mongodb-wait: ## Attendre le compte de supervision MongoDB
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready workspaces.tf.m.upbound.io/mongodb-monitoring --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-platforms-apply: ## Réconcilier le registre des plateformes OTel (topics et ACL)
	@$(KUBECTL) apply -f $(CROSSPLANE_ROOT)/platforms.yaml

crossplane-kafka-wait: ## Attendre les comptes, topics et ACL Kafka
	@$(KUBECTL) wait --for=condition=Ready otelplatforms.observability.lab.io --all --timeout=$(CROSSPLANE_TIMEOUT)
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready users.user.kafka.m.crossplane.io,accesscontrollists.acl.kafka.m.crossplane.io,topics.topic.kafka.m.crossplane.io --all --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-postgresql-wait: ## Attendre la configuration PostgreSQL
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready extensions.postgresql.sql.m.crossplane.io,roles.postgresql.sql.m.crossplane.io,grants.postgresql.sql.m.crossplane.io --all --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-elastic-wait: ## Attendre Elasticsearch déclaré (ILM, pipelines, clé API OTel)
	@$(KUBECTL) -n elastic-stack wait --for=condition=Ready workspaces.tf.m.upbound.io/elasticsearch --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-fleet-wait: ## Attendre les packages et policies Fleet déclarés
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready workspaces.tf.m.upbound.io/fleet --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-kibana-wait: ## Attendre les objets Kibana déclarés (data view, règles d'alerte, dashboards)
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready workspaces.tf.m.upbound.io/kibana-saved-objects workspaces.tf.m.upbound.io/kibana-alerting --timeout=$(CROSSPLANE_TIMEOUT)
	@$(KUBECTL) -n crossplane-system wait --for=condition=Ready requests.http.m.crossplane.io -l lab.io/managed-by=kibana-requests --timeout=$(CROSSPLANE_TIMEOUT)

crossplane-status: ## État des ressources gérées par Crossplane
	@$(KUBECTL) get providers.pkg.crossplane.io,functions.pkg.crossplane.io
	@$(KUBECTL) get otelplatforms.observability.lab.io
	@$(KUBECTL) get applications.apps.lab.io -A
	@$(KUBECTL) get managed -A
