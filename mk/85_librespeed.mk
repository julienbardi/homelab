# ============================================================
# LibreSpeed
# ============================================================

LIBRESPEED_DIR := $(REPO_ROOT)/librespeed

LIBRESPEED_COMPOSE_FILE := $(LIBRESPEED_DIR)/docker-compose.yml

COMPOSE_LIBRESPEED := docker compose -f $(LIBRESPEED_COMPOSE_FILE)

.PHONY: \
	librespeed-deploy \
	librespeed-up \
	librespeed-down \
	librespeed-restart \
	librespeed-logs

librespeed-deploy:
	@test -f "$(LIBRESPEED_COMPOSE_FILE)" || { \
		echo "❌ Missing $(LIBRESPEED_COMPOSE_FILE)"; \
		exit 1; \
	}
	@docker compose -f "$(LIBRESPEED_COMPOSE_FILE)" up -d

librespeed-up: librespeed-deploy

librespeed-down:
	$(COMPOSE_LIBRESPEED) down

librespeed-restart:
	$(COMPOSE_LIBRESPEED) restart

librespeed-logs:
	$(COMPOSE_LIBRESPEED) logs -f