# --------------------------------------------------------------------
# mk/00_icons.mk — Canonical icon definitions (contract-governed)
# --------------------------------------------------------------------
# These icons are normative. They MUST match the Output icon semantics
# contract in contracts.inc. No other icons may be used in operator-
# visible output unless the contract is amended.
# --------------------------------------------------------------------

SUCCESS_ICON   := "✅"
FAIL_ICON      := "❌"
WARN_ICON      := "⚠️"
INFO_ICON      := "ℹ️"
UNCHANGED_ICON := $(INFO_ICON)

# --------------------------------------------------------------------
# CONTRACT CHECK: Output icon semantics
# --------------------------------------------------------------------
# Enforces that only canonical icons appear in operator-visible output.
# Allowed icons (whitelist):
#   - $(SUCCESS_ICON)
#   - $(FAIL_ICON)
#   - $(WARN_ICON)
#   - $(INFO_ICON)
#   - $(UNCHANGED_ICON)
#
# Any other emoji or symbol in scripts/ or mk/ is a contract violation.
# --------------------------------------------------------------------

.PHONY: check-icons
check-icons:
	@echo "Checking icon usage against contract..."
	@violations=0; \
	allowed='✅|❌|⚠️|ℹ️'; \
	for f in scripts/*.sh scripts/*/*.sh; do \
		if grep -nE '[^ -~]' $$f | grep -Ev "$$allowed" >/dev/null; then \
			echo "❌ Non-canonical icon detected in $$f"; \
			grep -nE '[^ -~]' $$f | grep -Ev "$$allowed" || true; \
			violations=1; \
		fi; \
	done; \
	if [ $$violations -ne 0 ]; then \
		echo "❌ Icon contract violation detected"; \
		exit 1; \
	fi; \
	echo "✅ Icon usage complies with contract"

# --------------------------------------------------------------------
# INTROSPECTION: List all icons used in the repository
# --------------------------------------------------------------------
# Produces a frequency-sorted list of all non-ASCII characters found in
# operator-visible scripts. This is NOT an enforcement target.
# --------------------------------------------------------------------

.PHONY: list-icons-by-script
list-icons-by-script:
	@echo "Listing all non-ASCII glyphs and the scripts where they appear..."
	@rg -o '[^\x00-\x7F]+' scripts | tools/list_icons_by_script.py














