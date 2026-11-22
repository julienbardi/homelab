# mk/netbird.mk — Included by top-level Makefile

# Correct NetBird directory path
NETBIRD_DIR := $(REPO_ROOT)/netbird

NETBIRD_COMPOSE_FILE := $(NETBIRD_DIR)/docker-compose.yml
NETBIRD_TEMPLATE_FILE := $(NETBIRD_DIR)/config.yaml.template
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

.PHONY: render-netbird-config

render-netbird-config:
	@$(call WITH_SECRETS, \
		[ "$(VERBOSE)" -lt "1" ] || echo "📝 Rendering NetBird config from template..."; \
		tmp="$$(mktemp)"; \
		trap 'rm -f "$$tmp"' EXIT; \
		export NB_AUTH_SECRET="$$netbird_auth_secret"; \
		export NB_ENCRYPTION_KEY="$$netbird_encryption_key"; \
		envsubst < "$(NETBIRD_TEMPLATE_FILE)" > "$$tmp"; \
		rc=0; \
		$(call install_file,"$$tmp",$(NETBIRD_CONFIG_FILE),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
		case "$${rc:-0}" in \
			0|$(INSTALL_IF_CHANGED_EXIT_CHANGED)) ;; \
			*) exit "$$rc" ;; \
		esac \
	)


deploy-netbird-compose: render-netbird-config $(NETBIRD_COMPOSE_FILE) ensure-state-dirs
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "📦 Checking NetBird compose + config changes..."; fi; \
	changed=0; rc=0; \
	$(call install_file,$(NETBIRD_COMPOSE_FILE),$(NETBIRD_COMPOSE_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 docker-compose.yml changed — scheduling NetBird restart"; \
		touch $(NETBIRD_RESTART_STAMP); \
	fi; \
	\
	changed=0; rc=0; \
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

netbird-deploy: deploy-nas-caddyfile deploy-netbird-compose
	@if [ ! -f "$(NETBIRD_RESTART_STAMP)" ]; then \
		[ "$(VERBOSE)" -lt "1" ] || echo "🟢 NetBird already up-to-date"; \
	else \
		$(call WITH_SECRETS, \
			echo "🧹 Cleaning up any existing NetBird stack..."; \
			$(COMPOSE_NETBIRD) down --remove-orphans 2>/dev/null || true; \
			docker rm -f netbird-server netbird-dashboard netbird-crowdsec 2>/dev/null || true; \
			\
			export LAN_ROUTER="$(LAN_ROUTER)"; \
			export LAN_NAS="$(LAN_NAS)"; \
			export INFOMANIAK_ACCESS_TOKEN="$$infomaniak_api_token"; \
			export ACME_EMAIL="$$acme_email"; \
			export NB_PROXY_DOMAIN="$$ddns_netbird_domain"; \
			export NB_PROXY_TOKEN="$$netbird_proxy_token"; \
			\
			echo "🚀 Ensuring NetBird server is running..."; \
			$(COMPOSE_NETBIRD) up -d netbird-server; \
			\
			for i in $$(seq 1 30); do \
				if docker exec netbird-server true >/dev/null 2>&1; then \
					break; \
				fi; \
				sleep 1; \
			done; \
			\
			docker exec netbird-server true >/dev/null 2>&1 || { \
				echo "❌ netbird-server failed to become ready"; \
				exit 1; \
			}; \
			\
			if [ -z "$$NB_PROXY_TOKEN" ] || [ "$$NB_PROXY_TOKEN" = "null" ]; then \
				echo "🔐 Generating proxy token in RAM..."; \
				TOKEN_OUTPUT=$$(docker exec -i netbird-server /go/bin/netbird-server --config /etc/netbird/config.yaml admin token create --name proxy-token-$$(date +%s)) && \
				export NB_PROXY_TOKEN=$$(echo "$$TOKEN_OUTPUT" | grep "Token:" | awk '{print $$2}'); \
			fi; \
			\
			if [ -z "$$NB_PROXY_TOKEN" ]; then \
				echo "❌ Error: Could not obtain NB_PROXY_TOKEN"; \
				exit 1; \
			fi; \
			\
			echo "📦 Applying full docker compose stack with in-memory secrets..."; \
			$(COMPOSE_NETBIRD) up -d; \
			rm -f $(NETBIRD_RESTART_STAMP) \
		); \
	fi

###############################################################################
# Convenience targets
###############################################################################

netbird-up: netbird-deploy

netbird-down:
	@echo "🛑 Stopping NetBird stack..."; \
	$(COMPOSE_NETBIRD) down

netbird-restart:
	@echo "🔄 Restarting NetBird stack..."; \
	$(COMPOSE_NETBIRD) restart

netbird-logs:
	$(COMPOSE_NETBIRD) logs -f

netbird-reset:
	@rm -f $(NETBIRD_COMPOSE_SHADOW) $(NETBIRD_CONFIG_SHADOW) $(NETBIRD_RESTART_STAMP)