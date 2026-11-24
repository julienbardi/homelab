# ============================================================
# LibreSpeed
# ============================================================

LIBRESPEED_DIR := $(REPO_ROOT)/librespeed
LIBRESPEED_COMPOSE_FILE := $(LIBRESPEED_DIR)/docker-compose.yml
COMPOSE_LIBRESPEED := docker compose -p librespeed -f $(LIBRESPEED_COMPOSE_FILE)

.PHONY: \
	librespeed-deploy \
	librespeed-up \
	librespeed-down \
	librespeed-restart \
	librespeed-logs \
	librespeed-upgrade \
	librespeed-status

librespeed-deploy:
	$(call require_file,$(LIBRESPEED_COMPOSE_FILE))
	$(COMPOSE_LIBRESPEED) up -d

librespeed-up: librespeed-deploy

librespeed-down:
	$(call librespeed_require_compose)
	$(COMPOSE_LIBRESPEED) down

librespeed-restart:
	$(call librespeed_require_compose)
	$(COMPOSE_LIBRESPEED) restart

librespeed-logs:
	$(call librespeed_require_compose)
	$(COMPOSE_LIBRESPEED) logs -f

librespeed-upgrade:
	$(call librespeed_require_compose)
	@echo "⬇️ Pulling LibreSpeed image..."
	$(COMPOSE_LIBRESPEED) pull
	@echo "🚀 Recreating LibreSpeed..."
	$(COMPOSE_LIBRESPEED) up -d --force-recreate

librespeed-status:
	$(call librespeed_require_compose)
	$(COMPOSE_LIBRESPEED) ps