# ============================================================
# mk/20_gitignore.mk — externalized invariants
# ============================================================

.PHONY: lint-gitignore
lint-gitignore:
	@./scripts/gitignore-check.sh

.PHONY: check-no-plaintext-secrets
check-no-plaintext-secrets:
	@./scripts/secrets-check.sh

.PHONY: repo-preflight
repo-preflight:
	@echo "🚦 Running repo-preflight..."
	@fails=0; \
	./scripts/gitignore-check.sh || fails=1; \
	./scripts/secrets-check.sh || fails=1; \
	if [ $$fails -ne 0 ]; then \
		echo "❌ repo-preflight FAILED"; \
		exit 1; \
	fi; \
	echo "✅ repo-preflight OK"
