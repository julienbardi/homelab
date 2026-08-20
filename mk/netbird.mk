# mk/netbird.mk — Included by top-level Makefile

# Correct NetBird directory path
NETBIRD_DIR := $(REPO_ROOT)/netbird

NETBIRD_COMPOSE_FILE := $(NETBIRD_DIR)/docker-compose.yml
NETBIRD_CONFIG_FILE  := $(NETBIRD_DIR)/config.yaml
NETBIRD_DYNAMIC_FILE := $(NETBIRD_DIR)/traefik-dynamic.yaml

COMPOSE_NETBIRD := docker compose -f $(NETBIRD_COMPOSE_FILE)

# Shadow files (user-level)
NETBIRD_COMPOSE_SHADOW := $(STAMP_DIR_USER)/netbird_compose.shadow
NETBIRD_CONFIG_SHADOW  := $(STAMP_DIR_USER)/netbird_config.shadow

# Restart stamps
NETBIRD_RESTART_STAMP := $(STAMP_DIR_USER)/netbird_restart.stamp

.PHONY: netbird-up netbird-down netbird-restart netbird-logs netbird-deploy \
		deploy-netbird-dynamic deploy-netbird-compose

###############################################################################
# Traefik dynamic configuration deployment
###############################################################################

deploy-netbird-dynamic: ensure-state-dirs
	@changed=0; rc=0; \
	$(call install_file,$(NETBIRD_DYNAMIC_FILE),/etc/traefik/dynamic/netbird.yml,root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 netbird.yml updated — restarting Traefik"; \
		docker restart netbird-traefik-v2; \
	fi

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
# NetBird stack deployment (idempotent)
###############################################################################

netbird-deploy: deploy-netbird-dynamic deploy-netbird-compose
	@if [ -f "$(NETBIRD_RESTART_STAMP)" ]; then \
		echo "🚀 Redeploying NetBird stack..."; \
		$(COMPOSE_NETBIRD) up -d; \
		rm -f $(NETBIRD_RESTART_STAMP); \
	else \
		echo "✔ NetBird stack unchanged — no redeploy needed"; \
	fi

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
