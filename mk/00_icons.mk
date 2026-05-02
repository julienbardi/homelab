# --------------------------------------------------------------------
# mk/00_icons.mk — Canonical icon definitions (contract-governed)
# --------------------------------------------------------------------

SUCCESS_ICON   := "✅"
FAIL_ICON      := "❌"
WARN_ICON      := "⚠️"
INFO_ICON      := "ℹ️"
UNCHANGED_ICON := $(INFO_ICON)

# Canonical approved icons (inline contract)
# NOTE: No spaces, no quotes — this is a raw character whitelist.
#APPROVED_ICONS := 📝📦🔧🛠️✨🔄🔐⚙️ℹ️⚠️❌🚀🎉🧹📊🛡️📍
# Expanded approved icons (auto-derived from repo)
APPROVED_ICONS := 📝📦🔧🛠️✨🔄🔐⚙️ℹ️⚠️❌🚀🎉🧹📊🛡️📍✅

.PHONY: check-icons
check-icons:
	@echo "🔍 Checking icon usage against contract in scripts, mk/, and Makefile..."
	@allowed="$(APPROVED_ICONS)"; \
	find scripts mk Makefile -type f \( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) -print0 | \
	xargs -0 -P $(N_WORKERS) grep -nP "[^[:print:][:space:]$${allowed}]" | \
	grep -v "mk/00_icons.mk" > .icon_errors 2>/dev/null || true; \
	if [ -s .icon_errors ]; then \
		echo "❌ Non-canonical icon(s) detected (Non-breaking):"; \
		cat .icon_errors; \
	else \
		echo "📦 All icons in scripts and Makefiles comply with contract"; \
	fi; \
	rm -f .icon_errors; \
	exit 0

.PHONY: fix-icons
fix-icons:
	@echo "✨ Normalizing icons to canonical contract..."
	@allowed="$(APPROVED_ICONS)"; \
	find scripts mk Makefile -type f \( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) -print0 | \
	xargs -0 sed -i \
		-e 's/✔️/✅/g' \
		-e 's/❗/⚠️/g' \
		-e 's/‼️/⚠️/g' \
		-e 's/➕/✨/g' \
		-e 's/→/➡️/g' \
		-e 's/↪️/➡️/g' \
		-e 's/➜/➡️/g'
	@echo "📝 Canonical replacements applied"
	@echo "📦 Icons normalized to canonical contract."