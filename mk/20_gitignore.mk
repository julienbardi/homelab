# ============================================================
# mk/20_gitignore.mk — externalized invariants
# ============================================================

.PHONY: lint-gitignore
lint-gitignore:
	@./scripts/gitignore-check.sh

REPO_PREFLIGHT_SCRIPT := /usr/local/bin/secrets-check.sh

.PHONY: repo-preflight
repo-preflight: $(REPO_PREFLIGHT_SCRIPT)
	@echo "🚨 Running repo-preflight..."
	@$(REPO_PREFLIGHT_SCRIPT)
	@fails=0; \
	./scripts/gitignore-stamp.sh || fails=1; \
	./scripts/secrets-stamp.sh || fails=1; \
	./scripts/detect-unauthorized-lan-ips.sh || fails=1; \
	if [ $$fails -ne 0 ]; then \
		echo "❌ repo-preflight FAILED"; \
		exit 1; \
	fi; \
	echo "✅ repo-preflight OK"
