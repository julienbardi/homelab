# mk/85_authentik.mk

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

.PHONY: authentik-version
authentik-version:
	@grep -n 'ghcr.io/goauthentik/server:' $(AUTHENTIK_COMPOSE_FILE)

.PHONY: authentik-version-check
authentik-version-check:
	@echo "Configured:"
	@grep -oE 'ghcr.io/goauthentik/server:[^ ]+' $(AUTHENTIK_COMPOSE_FILE)
	@echo
	@echo "Latest:"
	@curl -fsSL https://api.github.com/repos/goauthentik/authentik/releases/latest \
	| jq -r .tag_name

.PHONY: authentik-upgrade-check
authentik-upgrade-check:
	@CURRENT=$$(grep -oE 'ghcr.io/goauthentik/server:[^ ]+' $(AUTHENTIK_COMPOSE_FILE) | head -1 | cut -d: -f2-); \
	LATEST=$$(curl -fsSL https://api.github.com/repos/goauthentik/authentik/releases/latest | jq -r .tag_name | sed 's|^version/||'); \
	echo "Current: $$CURRENT"; \
	echo "Latest : $$LATEST"; \
	if [ "$$CURRENT" = "$$LATEST" ]; then \
		echo "✅ Authentik is up to date"; \
	else \
		echo "⚠️  Upgrade available"; \
		echo "Edit: $(AUTHENTIK_COMPOSE_FILE)"; \
		echo "Replace: $$CURRENT"; \
		echo "With:    $$LATEST"; \
	fi