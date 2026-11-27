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

.PHONY: immich-status
immich-status:
	@sudo pct exec $(IMMICH_CT) -- docker ps

.PHONY: immich-upgrade
immich-upgrade:
	@echo "📦 Upgrading Immich..."
	@sudo pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose pull && \
		docker compose up -d \
	'

.PHONY: immich-logs
immich-logs:
	@sudo pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose logs --tail=50 immich-server \
	'

.PHONY: immich-follow
immich-follow:
	@sudo pct exec $(IMMICH_CT) -- sh -c '\
		cd /opt/immich && \
		docker compose logs -f immich_server \
	'