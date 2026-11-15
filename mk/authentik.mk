# mk/authentik.mk

AUTHENTIK_DIR := $(REPO_ROOT)/authentik
AUTHENTIK_COMPOSE_FILE := $(AUTHENTIK_DIR)/docker-compose.yml

COMPOSE_AUTHENTIK := docker compose -f $(AUTHENTIK_COMPOSE_FILE)

.PHONY: authentik-deploy authentik-up authentik-down authentik-restart authentik-logs

authentik-deploy: secrets-ready
	@echo "🚀 Deploying Authentik..."
	@$(call WITH_SECRETS, \
		export AUTHENTIK_SECRET_KEY="$$AUTHENTIK_SECRET_KEY"; \
		export AUTHENTIK_POSTGRES_PASSWORD="$$AUTHENTIK_POSTGRES_PASSWORD"; \
		$(COMPOSE_AUTHENTIK) up -d; \
	)

authentik-up: authentik-deploy

authentik-down:
	$(COMPOSE_AUTHENTIK) down

authentik-restart:
	$(COMPOSE_AUTHENTIK) restart

authentik-logs:
	$(COMPOSE_AUTHENTIK) logs -f
