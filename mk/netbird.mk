# mk/netbird.mk — Included by top-level Makefile

# Correct NetBird directory path
NETBIRD_DIR := $(REPO_ROOT)/netbird

NETBIRD_COMPOSE_FILE := $(NETBIRD_DIR)/docker-compose.yml
NETBIRD_CONFIG_FILE  := $(NETBIRD_DIR)/config.yaml

COMPOSE_NETBIRD := docker compose -f $(NETBIRD_COMPOSE_FILE)

# Shadow files (user-level)
NETBIRD_COMPOSE_SHADOW := $(STAMP_DIR_USER)/netbird_compose.shadow
NETBIRD_CONFIG_SHADOW  := $(STAMP_DIR_USER)/netbird_config.shadow

# Restart stamps
NETBIRD_RESTART_STAMP := $(STAMP_DIR_USER)/netbird_restart.stamp

.PHONY: netbird-up netbird-down netbird-restart netbird-logs netbird-deploy \
        deploy-netbird-compose netbird-rotate-token

###############################################################################
# NetBird Proxy Token Rotation
###############################################################################

netbird-rotate-token: ensure-state-dirs
	@echo "🔄 Token rotation requested — scheduling NetBird stack redeploy..."
	@touch $(NETBIRD_RESTART_STAMP)

###############################################################################
# NetBird compose + config deployment (idempotent)
###############################################################################

deploy-netbird-compose: $(NETBIRD_COMPOSE_FILE) $(NETBIRD_CONFIG_FILE) ensure-state-dirs
	@echo "📦 Checking NetBird compose + config changes..."

	@changed=0; rc=0; \
	$(call install_file,$(NETBIRD_COMPOSE_FILE),$(NETBIRD_COMPOSE_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 docker-compose.yml changed — scheduling NetBird restart"; \
		touch $(NETBIRD_RESTART_STAMP); \
	fi

	@changed=0; rc=0; \
	$(call install_file,$(NETBIRD_CONFIG_FILE),$(NETBIRD_CONFIG_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 config.yaml changed — scheduling NetBird restart"; \
		touch $(NETBIRD_RESTART_STAMP); \
	fi

###############################################################################
# NetBird stack deployment (idempotent & zero-at-rest secrets)
###############################################################################

netbird-deploy: deploy-netbird-compose
	@echo "🧹 Cleaning up any existing NetBird stack..."
	@$(COMPOSE_NETBIRD) down --remove-orphans 2>/dev/null || true; \
	docker rm -f netbird-server netbird-dashboard netbird-crowdsec 2>/dev/null || true; \
	\
	echo "📦 Decrypting secrets into memory..."; \
	export LAN_ROUTER="$(LAN_ROUTER)"; \
	export LAN_NAS="$(LAN_NAS)"; \
	SECRETS_DEC=$$(sops -d $(SECRETS_FILE)); \
	export INFOMANIAK_ACCESS_TOKEN=$$(echo "$$SECRETS_DEC" | yq e '.infomaniak_api_token' -); \
	export ACME_EMAIL=$$(echo "$$SECRETS_DEC" | yq e '.acme_email' -); \
	export NB_PROXY_DOMAIN=$$(echo "$$SECRETS_DEC" | yq e '.ddns_netbird_domain' -); \
	export NB_PROXY_TOKEN=$$(echo "$$SECRETS_DEC" | yq e '.netbird_proxy_token' -); \
	\
	echo "🚀 Ensuring NetBird server is running..."; \
	$(COMPOSE_NETBIRD) up -d netbird-server; \
	sleep 3; \
	\
	if [ -z "$$NB_PROXY_TOKEN" ] || [ "$$NB_PROXY_TOKEN" = "null" ]; then \
		echo "🔐 Generating proxy token in RAM..."; \
		TOKEN_OUTPUT=$$(docker exec -i netbird-server /go/bin/netbird-server --config /etc/netbird/config.yaml admin token create --name proxy-token-$$(date +%s)) && \
		export NB_PROXY_TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep "Token:" | awk '{print $$2}'); \
	fi; \
	if [ -z "$$NB_PROXY_TOKEN" ]; then \
		echo "❌ Error: Could not obtain NB_PROXY_TOKEN"; \
		exit 1; \
	fi; \
	\
	echo "📦 Applying full docker compose stack with in-memory secrets..."; \
	$(COMPOSE_NETBIRD) up -d; \
	rm -f $(NETBIRD_RESTART_STAMP)

###############################################################################
# Convenience targets
###############################################################################

netbird-up: netbird-deploy

netbird-down:
	@echo "🛑 Stopping NetBird stack..."
	$(COMPOSE_NETBIRD) down

netbird-restart:
	@echo "🔄 Restarting NetBird stack..."
	$(COMPOSE_NETBIRD) restart

netbird-logs:
	$(COMPOSE_NETBIRD) logs -f

netbird-reset:
	rm -f $(NETBIRD_COMPOSE_SHADOW) $(NETBIRD_CONFIG_SHADOW) $(NETBIRD_RESTART_STAMP)