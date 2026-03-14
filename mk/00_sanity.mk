# mk/00_sanity.mk
#
# Invariant:
# - Make never executes scripts from the repo
# - All executable tools must be installed under $(INSTALL_PATH)
# - Targets depend on installed artifacts, not source files
# ------------------------------------------------------------

.PHONY: assert-sanity assert-no-repo-exec assert-scripts-layout
assert-sanity: \
	assert-no-repo-exec \
	assert-scripts-layout

# Prevents race conditions and ensures we don't accidentally execute
# non-bootstrapped scripts from the working directory.
assert-no-repo-exec:
ifneq ($(filter -j%,$(MAKEFLAGS)),)
	@grep -R 'scripts/.*\.sh' --include='*.mk' \
		--exclude=00_sanity.mk \
		--exclude=01_common.mk \
		--exclude-dir=archive . >/dev/null && \
	{ \
		echo "🚫 Parallel execution (-j) is not supported."; \
		echo "   Safety checks detected repo-local script references during graph expansion."; \
		echo "   No scripts were executed."; \
		echo "   Rerun without -j (or use -j1)."; \
		exit 1; \
	}
endif

# Ensures all scripts reside in approved functional subdirectories.
assert-scripts-layout:
	@bad=$$(find "$(MAKEFILE_DIR)scripts" \
		-mindepth 2 -type f -name '*.sh' \
		! -path '*/helpers/*' \
		! -path '*/lib/*' \
		! -path '*/client/*' \
		! -path '*/setup/*' \
		! -path '*/audit/*' \
		! -path '*/deploy/*' \
		! -path '*/router/*' \
		! -path '*/common/*' \
		-print); \
	if [ -n "$$bad" ]; then \
		echo "❌ Layout Violation: Unexpected executable scripts found:"; \
		echo "$$bad" | sed 's/^/   - /'; \
		echo ""; \
		echo "👉 Scripts must be organized into functional subdirectories."; \
		exit 1; \
	fi