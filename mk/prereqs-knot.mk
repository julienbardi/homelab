# mk/prereqs-knot.mk — kdig package installation (stamp pattern)
# ------------------------------------------------------------
# CONTRACT:
# - Installation is idempotent using stamps
# - Uses non-interactive package management
# ------------------------------------------------------------

STAMP_KDIG := $(STAMP_DIR_ROOT)/kdig.stamp

.PHONY: install-kdig remove-kdig verify-kdig

install-kdig: ensure-state-dirs
	@set -euo pipefail; \
	if [ -f "$(STAMP_KDIG)" ] && [ ! -L "$(STAMP_KDIG)" ] && dpkg -s knot-dnsutils >/dev/null 2>&1; then \
		_INST_VER="$$(dpkg-query -W -f='$${Version}' knot-dnsutils 2>/dev/null || echo "")"; \
		_S_VER="$$(grep '^version=' "$(STAMP_KDIG)" 2>/dev/null | cut -d= -f2- || echo "")"; \
		if [ -n "$$_INST_VER" ] && [ "$$_S_VER" = "$$_INST_VER" ]; then \
			echo "⏩ kdig unchanged (fast-path OK)"; \
			exit 0; \
		fi; \
	fi; \
	echo "📦 Installing kdig (knot-dnsutils)..."; \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive \
		apt-get -o Dpkg::Options::="--force-confdef" \
		        -o Dpkg::Options::="--force-confold" \
		        install -y knot-dnsutils || { echo "❌ kdig installation failed"; exit 1; }; \
	$(run_as_root) mkdir -p "$$(dirname "$(STAMP_KDIG)")"; \
	_INST_VER="$$(dpkg-query -W -f='$${Version}' knot-dnsutils 2>/dev/null || echo "unknown")"; \
	{ \
		echo "version=$$_INST_VER"; \
		echo "sha256=$$(dpkg -L knot-dnsutils 2>/dev/null | xargs sha256sum 2>/dev/null | awk '{print $$1}' | sha256sum | awk '{print $$1}' || echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")"; \
		echo "owner=root"; \
		echo "group=root"; \
		echo "perm=0755"; \
		echo "type=package"; \
	} | $(run_as_root) tee "$(STAMP_KDIG)" >/dev/null; \
	echo "✅ kdig installed"

remove-kdig:
	@$(run_as_root) sh -c ' \
		apt-get purge -y knot-dnsutils >/dev/null 2>&1 || true; \
		apt-get autoremove -y >/dev/null 2>&1 || true; \
		rm -f "$(STAMP_KDIG)"; \
	'; \
	echo "🗑️ kdig removed"

verify-kdig:
	@if ! dpkg -s knot-dnsutils >/dev/null 2>&1; then \
		echo "❌ kdig is not installed"; \
		exit 1; \
	fi; \
	echo "✅ kdig package verified"