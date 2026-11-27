# ============================================================================
# mk/85_immich.mk
# ============================================================================

export IMMICH_CT := 225

IMMICH_DIR := $(REPO_ROOT)/immich

IMMICH_COMPOSE_TEMPLATE := $(IMMICH_DIR)/docker-compose.yml.in
IMMICH_ENV_TEMPLATE := $(IMMICH_DIR)/.env.in

IMMICH_REMOTE_DIR := /opt/immich

IMMICH_COMPOSE_FILE := $(IMMICH_REMOTE_DIR)/docker-compose.yml
IMMICH_ENV_FILE := $(IMMICH_REMOTE_DIR)/.env

IMMICH_COMPOSE_SHADOW := $(STAMP_DIR_USER)/immich_compose.shadow
IMMICH_ENV_SHADOW := $(STAMP_DIR_USER)/immich_env.shadow

IMMICH_RESTART_STAMP := $(STAMP_DIR_USER)/immich_restart.stamp

.PHONY: deploy-immich-config

deploy-immich-config: ensure-state-dirs
	@$(call require_file,$(IMMICH_COMPOSE_TEMPLATE))
	@$(call require_file,$(IMMICH_ENV_TEMPLATE))

	@tmp_compose="$$(mktemp)"; \
	tmp_env="$$(mktemp)"; \
	trap 'rm -f "$$tmp_compose" "$$tmp_env"' EXIT; \
	RENDER_GID="$$(getent group render | cut -d: -f3)"; \
	sed "s|@RENDER_GID@|$$RENDER_GID|g" \
		< "$(IMMICH_COMPOSE_TEMPLATE)" \
		> "$$tmp_compose"; \
	cp "$(IMMICH_ENV_TEMPLATE)" "$$tmp_env"; \
	\
	changed=0; rc=0; \
	$(call install_file,"$$tmp_compose",$(IMMICH_COMPOSE_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
	0) ;; \
	$(INSTALL_IF_CHANGED_EXIT_CHANGED)) \
		echo "🔄 docker-compose.yml changed"; \
		changed=1 ;; \
	*) exit "$$rc" ;; \
	esac; \
	\
	rc=0; \
	$(call install_file,"$$tmp_env",$(IMMICH_ENV_SHADOW),$(shell id -u),$(shell id -g),0644) || rc=$$?; \
	case "$${rc:-0}" in \
	0) ;; \
	$(INSTALL_IF_CHANGED_EXIT_CHANGED)) \
		echo "🔄 .env changed"; \
		changed=1 ;; \
	*) exit "$$rc" ;; \
	esac; \
	\
	if [ $$changed -eq 1 ]; then \
		echo "🔄 Immich configuration changed"; \
		$(run_as_root) pct exec $(IMMICH_CT) -- \
			install -d -m 0755 "$(IMMICH_REMOTE_DIR)"; \
		$(run_as_root) pct push $(IMMICH_CT) \
			"$$tmp_compose" "$(IMMICH_COMPOSE_FILE)"; \
		$(run_as_root) pct push $(IMMICH_CT) \
			"$$tmp_env" "$(IMMICH_ENV_FILE)"; \
		touch $(IMMICH_RESTART_STAMP); \
	fi

.PHONY: immich-deploy

immich-deploy: deploy-immich-config
	@if [ -f "$(IMMICH_RESTART_STAMP)" ]; then \
		echo "🚀 Applying Immich stack..."; \
		$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
			cd /opt/immich && \
			docker compose up -d'; \
		rm -f $(IMMICH_RESTART_STAMP); \
	else \
		[ "$(VERBOSE)" -lt "1" ] || echo "🟢 Immich already up-to-date"; \
	fi

.PHONY: immich-status
immich-status:
	@$(run_as_root) pct exec $(IMMICH_CT) -- docker ps

.PHONY: immich-upgrade
immich-upgrade:
	@echo "📦 Upgrading Immich..."
	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose pull && \
		docker compose up -d \
	'

.PHONY: immich-logs
immich-logs:
	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose logs --tail=50 immich-server \
	'

.PHONY: immich-follow
immich-follow:
	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose logs -f immich_server \
	'