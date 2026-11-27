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
	\
	RENDER_GID="$$(getent group render | cut -d: -f3 || true)"; \
	[ -n "$$RENDER_GID" ] || { \
		echo "❌ Failed to resolve render group GID"; \
		exit 1; \
	}; \
	\
	sed "s|@RENDER_GID@|$$RENDER_GID|g" \
		< "$(IMMICH_COMPOSE_TEMPLATE)" \
		> "$$tmp_compose"; \
	\
	cp "$(IMMICH_ENV_TEMPLATE)" "$$tmp_env"; \
	\
	changed=0; \
	\
	if ! cmp -s "$$tmp_compose" "$(IMMICH_COMPOSE_SHADOW)" 2>/dev/null; then \
		echo "🔄 docker-compose.yml changed"; \
		changed=1; \
	fi; \
	\
	if ! cmp -s "$$tmp_env" "$(IMMICH_ENV_SHADOW)" 2>/dev/null; then \
		echo "🔄 .env changed"; \
		changed=1; \
	fi; \
	\
	if [ $$changed -eq 1 ]; then \
		echo "🔄 Immich configuration changed"; \
		\
		$(run_as_root) pct exec $(IMMICH_CT) -- \
			install -d -m 0755 "$(IMMICH_REMOTE_DIR)"; \
		\
		$(run_as_root) pct push $(IMMICH_CT) \
			"$$tmp_compose" \
			"$(IMMICH_REMOTE_DIR)/.docker-compose.yml.new"; \
		\
		$(run_as_root) pct push $(IMMICH_CT) \
			"$$tmp_env" \
			"$(IMMICH_REMOTE_DIR)/.env.new"; \
		\
		$(run_as_root) pct exec $(IMMICH_CT) -- sh -eu -c '\
			cd "$(IMMICH_REMOTE_DIR)" && \
			mv .docker-compose.yml.new docker-compose.yml && \
			mv .env.new .env'; \
		\
		cp "$$tmp_compose" "$(IMMICH_COMPOSE_SHADOW).new"; \
		cp "$$tmp_env" "$(IMMICH_ENV_SHADOW).new"; \
		mv "$(IMMICH_COMPOSE_SHADOW).new" "$(IMMICH_COMPOSE_SHADOW)"; \
		mv "$(IMMICH_ENV_SHADOW).new" "$(IMMICH_ENV_SHADOW)"; \
		\
		touch "$(IMMICH_RESTART_STAMP)"; \
	fi


.PHONY: immich-deploy

immich-deploy: deploy-immich-config

	@if [ -f "$(IMMICH_RESTART_STAMP)" ]; then \
		echo "🚀 Applying Immich stack..."; \
		$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
			cd "$(IMMICH_REMOTE_DIR)" && \
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
		cd "$(IMMICH_REMOTE_DIR)" && \
		docker compose pull && \
		docker compose up -d \
	'

.PHONY: immich-logs
immich-logs:
	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
		cd "$(IMMICH_REMOTE_DIR)" && \
		docker compose logs --tail=50 immich-server \
	'

.PHONY: immich-follow
immich-follow:
	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -c '\
		cd "$(IMMICH_REMOTE_DIR)" && \
		docker compose logs -f immich-server \
	'

.PHONY: immich-gpu-verify

immich-gpu-verify:
	@echo "🎮 Verifying Immich GPU access..."

	@$(run_as_root) pct exec $(IMMICH_CT) -- sh -eu -c '\
		OK=0; \
		TOTAL=2; \
		for c in immich_server immich_machine_learning; do \
			if docker exec "$$c" head -c 0 /dev/dri/renderD128 >/dev/null 2>&1; then \
				echo "✅ $$c: renderD128 accessible"; \
				OK=$$((OK+1)); \
			else \
				echo "⚠️ $$c: cannot access /dev/dri/renderD128"; \
				echo "⚠️ Check /dev/dri mapping and render group membership"; \
			fi; \
		done; \
		echo "✅ Immich GPU verification completed ($$OK/$$TOTAL containers healthy)"'