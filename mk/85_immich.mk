# ============================================================================
# mk/85_immich.mk
# ============================================================================

export IMMICH_CT := 225

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