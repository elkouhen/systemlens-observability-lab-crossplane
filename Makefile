SHELL := /bin/bash
.DEFAULT_GOAL := help

ARCH_ROOT := architecture
ARCH_NAME := Hybride Fleet
SYSTEMLENS ?= systemlens
# Relatif à $(ARCH_ROOT), où la cible se place.
VM ?= ./scripts/vm

.PHONY: help architecture-status apps-architecture-graph apps-codeql-module-graph apm-install apm-audit vms-destroy ci ci-run

help: ## Afficher les tâches de l'architecture par défaut
	@printf 'Architecture par défaut : %s\n' '$(ARCH_NAME)'
	@printf 'Usage : make <cible>\n'
	@printf "  architecture-status  Afficher la configuration de l'architecture\n"
	@printf '  apps-architecture-graph  Indexer les sources Java et générer le graphe SystemLens\n'
	@printf '  apps-codeql-module-graph Analyser les dépendances de modules Java et actualiser le graphe\n'
	@printf '  apm-install          Installer le contexte APM déclaré dans apm.yml\n'
	@printf '  apm-audit            Auditer le contexte APM du projet\n'
	@printf '  vms-up               Démarrer et provisionner les quatre VM\n'
	@printf '  deploy               Déployer la plateforme et les applications après vms-up\n'
	@printf '  vms-destroy          Détruire les VM de l’architecture active\n'
	@printf "  ci-run               Exécuter les validations de l'architecture\n"
	@printf '  make <cible>         Déléguer la cible au bundle d’architecture\n'

architecture-status: ## Afficher la configuration de l'architecture
	@$(MAKE) -C $(ARCH_ROOT) architecture-status

apps-architecture-graph: ## Indexer les sources Java et générer le graphe SystemLens
	@command -v '$(SYSTEMLENS)' >/dev/null 2>&1 || { echo 'SystemLens absent : installez une version compatible avec import-facts.' >&2; exit 1; }
	@cd apps/supermarket-demo && \
	  '$(SYSTEMLENS)' doctor && \
	  '$(SYSTEMLENS)' index && \
	  jq empty architecture.application-inventory.json && \
	  jq empty architecture.supermarket.flows.json && \
	  flows_file=$$(mktemp architecture.systemlens-flows.json.XXXXXX) && \
	  trap 'rm -f "$$flows_file"' EXIT && \
	  '$(SYSTEMLENS)' flows --json > "$$flows_file" && \
	  mv "$$flows_file" architecture.systemlens-flows.json && \
	  '$(SYSTEMLENS)' import-facts architecture.ai-java.pass-004.json --namespace ai-java-architecture --complete && \
	  '$(SYSTEMLENS)' export microservices --html architecture.java.html --root-path .

apps-codeql-module-graph: ## Analyser les dépendances de modules Java avec CodeQL
	@command -v codeql >/dev/null 2>&1 || { echo 'CodeQL absent : installez la CLI et le pack codeql/java-all.' >&2; exit 1; }
	@cd apps/supermarket-demo && ./codeql/export-module-dependencies.sh

apm-install: ## Installer le contexte APM déclaré dans apm.yml
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm install

apm-audit: ## Auditer le contexte APM du projet
	@command -v apm >/dev/null 2>&1 || { echo "APM CLI absent : voir docs/agent-package-manager.md" >&2; exit 1; }
	@apm audit --ci

vms-destroy: ## Détruire les VM de l’architecture active
	@cd '$(ARCH_ROOT)' && '$(VM)' delete

ci: ## Exécuter les validations de l'architecture
	@$(MAKE) -C $(ARCH_ROOT) ci

ci-run: ## Exécuter les validations reproductibles de l'architecture
	@$(MAKE) -C $(ARCH_ROOT) ci-run

%:
	@$(MAKE) -C $(ARCH_ROOT) '$@'
