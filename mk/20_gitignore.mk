# ============================================================
# mk/20_gitignore.mk — externalized invariants
# ============================================================

# ------------------------------------------------------------
# Runtime script locations (single source of truth)
# ------------------------------------------------------------
RUNTIME_DIR := /usr/local/bin

STAMPS_SCRIPT          := $(RUNTIME_DIR)/stamps.sh
GITIGNORE_CHECK_SCRIPT := $(RUNTIME_DIR)/gitignore-check.sh
GITIGNORE_STAMP_SCRIPT := $(RUNTIME_DIR)/gitignore-stamp.sh
SECRETS_STAMP_SCRIPT   := $(RUNTIME_DIR)/secrets-stamp.sh
LAN_IP_CHECK_SCRIPT    := $(RUNTIME_DIR)/detect-unauthorized-lan-ips.sh
SECRETS_CHECK_SCRIPT   := $(RUNTIME_DIR)/secrets-check.sh

RUNTIME_SCRIPTS := \
	$(STAMPS_SCRIPT) \
	$(GITIGNORE_CHECK_SCRIPT) \
	$(GITIGNORE_STAMP_SCRIPT) \
	$(SECRETS_STAMP_SCRIPT) \
	$(LAN_IP_CHECK_SCRIPT) \
	$(SECRETS_CHECK_SCRIPT)

# ------------------------------------------------------------
# Fail early if any runtime script is missing
# ------------------------------------------------------------
$(RUNTIME_SCRIPTS):
	@echo "❌ Missing runtime script: $@"
	@echo "   Run 'make install-all' to install required scripts."
	@exit 1

# ------------------------------------------------------------
# Lint target
# ------------------------------------------------------------
.PHONY: lint-gitignore
lint-gitignore: $(GITIGNORE_CHECK_SCRIPT)
	@bash $(GITIGNORE_CHECK_SCRIPT)

# ------------------------------------------------------------
# Repo-preflight
# ------------------------------------------------------------
.PHONY: repo-preflight
repo-preflight: $(RUNTIME_SCRIPTS)
	@echo "🚨 Running repo-preflight..."
	@bash $(SECRETS_CHECK_SCRIPT)

	@fails=0; \
	bash $(GITIGNORE_STAMP_SCRIPT) --check || fails=1; \
	bash $(SECRETS_STAMP_SCRIPT) --check || fails=1; \
	bash $(LAN_IP_CHECK_SCRIPT) --check || fails=1; \
	if [ $$fails -ne 0 ]; then \
		echo "❌ repo-preflight FAILED"; \
		exit 1; \
	fi; \
	echo "✅ repo-preflight OK"
