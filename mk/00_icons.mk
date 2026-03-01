# --------------------------------------------------------------------
# mk/00_icons.mk — Canonical icon definitions (contract-governed)
# --------------------------------------------------------------------

SUCCESS_ICON   := "✅"
FAIL_ICON      := "❌"
WARN_ICON      := "⚠️"
INFO_ICON      := "ℹ️"
UNCHANGED_ICON := $(INFO_ICON)

.PHONY: check-icons
check-icons:
	@echo "🔍 Checking icon usage against contract in scripts, mk/, and Makefile..."
	@allowed=$$(cat tools/approved_icons.txt | tr -d '[:space:]'); \
	find scripts mk Makefile -type f \( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) -print0 | \
	xargs -0 -P $(N_WORKERS) grep -nP "[^[:print:][:space:]$${allowed}]" | \
	grep -v "mk/00_icons.mk" > .icon_errors 2>/dev/null || true; \
	if [ -s .icon_errors ]; then \
		echo "❌ Non-canonical icon(s) detected (Non-breaking):"; \
		cat .icon_errors; \
	else \
		echo "✅ All icons in scripts and Makefiles comply with contract"; \
	fi; \
	rm -f .icon_errors; \
	exit 0

.PHONY: fix-icons
fix-icons:
	@echo "🪄 Autocorrecting whitespace and standardizing symbols..."
	# 1. Heredoc injection to surgically overwrite corrupted lines in mk/00_prereqs.mk
	@python3 -c '\
	import sys; \
	lines = open("mk/00_prereqs.mk").readlines(); \
	lines[35] = "\t\t\techo \"⚠️  Cannot read net.ipv4.ip_forward (sysctl unavailable?)\"\n"; \
	lines[164] = "\t@echo \"⚠️  Fixing Tailscale APT repository (signed-by hygiene)\"\n"; \
	open("mk/00_prereqs.mk", "w").writelines(lines)'
	# 2. Global cleanup for non-breaking spaces and smart characters
	@find scripts mk Makefile -type f \( -name "*.sh" -o -name "*.mk" -o -name "Makefile" \) -print0 | \
	xargs -0 sed -i \
		-e 's/\xc2\xa0/ /g' \
		-e 's/\xe2\x80\x91/-/g' \
		-e 's/\xe2\x86\x92/->/g' \
		-e "s/['']/'/g" \
		-e 's/[""]/"/g' \
		-e 's/-/-/g'