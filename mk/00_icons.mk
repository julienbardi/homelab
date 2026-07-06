# --------------------------------------------------------------------
# mk/00_icons.mk — Canonical Icon Definitions (Contract-Governed)
# --------------------------------------------------------------------
# CONTRACT:
# - Icons used across Makefiles and scripts MUST come from APPROVED_ICONS.
# - Icons MUST be raw characters (no quotes, no spaces).
# - Normalization MUST be performed via `fix-icons`.
# - Violations are non-breaking but MUST be reported by `check-icons`.
# --------------------------------------------------------------------

# Canonical approved icons (raw character whitelist)
APPROVED_ICONS := \
✅📝📦🔧🛠️✨🔄⬆️➡️🔐⚙️ℹ️⚠️❌🚀🎉📊🛡️🔍🟢🔁🚚🚨🔒🔓🔑🌐📋📥🔌🛑🚫🏁🐍🔗⚪🟦🟩🟨📜🎯📡📌📸

# --------------------------------------------------------------------
# Icon Compliance Check
# --------------------------------------------------------------------
.PHONY: check-icons
check-icons:
	@echo "🔍 Checking icon usage against canonical contract..."

	# Convert APPROVED_ICONS into alternation: 📝📦🔧 ➡️ 📝|📦|🔧
	@approved_alt="$$(printf '%s' "$(APPROVED_ICONS)" | sed 's/\(.\)/\1|/g' | sed 's/|$$//')"; \

	# Full Unicode emoji detection (covers ALL emoji used in your repo)
	@emoji_pattern='[\x{1F000}-\x{1FAFF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{FE00}-\x{FE0F}]'; \

	# Scan repo for emoji, filter out approved ones
	find scripts mk Makefile -type f \
		 ! -name "00_icons.mk" \
		\( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) \
		-print0 | \
	xargs -0 grep -nP "$$emoji_pattern" | \
	grep -vE "$$approved_alt" > .icon_errors 2>/dev/null || true; \

	# Report violations
	if [ -s .icon_errors ]; then \
		echo "❌ Non-canonical icon(s) detected (non-breaking):"; \
		cat .icon_errors; \
	else \
		echo "📦 All icons comply with canonical contract"; \
	fi; \
	rm -f .icon_errors; \
	exit 0

# --------------------------------------------------------------------
# Icon Normalization
# --------------------------------------------------------------------
.PHONY: fix-icons
fix-icons:
	@echo "✨ Normalizing icons to canonical contract..."
	find scripts mk Makefile -type f \
		! -name "00_icons.mk" \
		\( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) \
		-print0 | \
	xargs -0 sed -i \
		-e 's/💾/📥/g' \
		-e 's/🔍️/🔍/g' \
		-e 's/📄/📋/g' \
		-e 's/📁/📋/g' \
		-e 's/📂/📋/g' \
		-e 's/📤/📥/g' \
		-e 's/📈/📊/g' \
		-e 's/📉/📊/g' \
		-e 's/🧩/🔧/g' \
		-e 's/🧠/🔧/g' \
		-e 's/🔎/🔍/g' \
		-e 's/🔬/🔍/g' \
		-e 's/🔥/⚠️/g' \
		-e 's/⚡/⚙️/g' \
		-e 's/👉/➡️/g' \
		-e 's/🧬/🔧/g' \
		-e 's/🆗/🟢/g' \
		-e 's/🚦/🚨/g' \
		-e 's/🛂/🛡️/g' \
		-e 's/✔/✅/g' \
		-e 's/👥//g' \
		-e 's/☐//g' \
		-e 's/🧼/✨/g' \
		-e 's/📍//g' \
		-e 's/🧹//g'

	@echo "📝 Canonical replacements applied"
	@echo "📦 Icons normalized to canonical contract."
