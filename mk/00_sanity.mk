# mk/00_sanity.mk
#
# Invariant:
# - Make never executes scripts from the repo
# - All executable tools must be installed under $(INSTALL_PATH)
# - Targets depend on installed artifacts, not source files

.PHONY: assert-sanity assert-no-repo-exec assert-scripts-layout
assert-sanity: \
	assert-no-repo-exec \
	assert-scripts-layout

assert-no-repo-exec:
	@! grep -R 'scripts/.*\.sh' --include='*.mk' \
		--exclude=00_sanity.mk \
		--exclude=01_common.mk \
		--exclude-dir=archive . || \
		{ echo "❌ Repo script execution detected"; exit 1; }

assert-scripts-layout:
	@bad=$$(find "$(HOMELAB_DIR)/scripts" \
		-mindepth 2 -type f -name '*.sh' \
		! -path '*/helpers/*' \
		! -path '*/lib/*' \
		! -path '*/client/*' \
		! -path '*/setup/*' \
		! -path '*/audit/*' \
		! -path '*/deploy/*' \
		-print); \
	if [ -n "$$bad" ]; then \
		echo "❌ Unexpected executable scripts found:"; \
		echo "$$bad" | sed 's/^/   - /'; \
		exit 1; \
	fi
