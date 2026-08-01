# ====================================================================
# mk/common/macros.mk — General Macros (APT, ACME, Git, Systemd, Tmpfiles)
# ====================================================================


# --------------------------------------------------------------------
# Systemd Helpers
# --------------------------------------------------------------------
define systemctl_daemon_reload
	$(run_as_root) systemctl daemon-reload
endef


# --------------------------------------------------------------------
# Git Helpers
# --------------------------------------------------------------------
define git_clone_or_fetch
	mkdir -p "$(1)"; \
	if [ -d "$(1)/.git" ]; then \
		cd "$(1)"; \
		git fetch --unshallow --tags --quiet 2>/dev/null || git fetch --tags --quiet; \
		if ! git checkout --quiet "$(3)" 2>/dev/null; then \
			cd ..; rm -rf "$(1)"; \
			git clone --quiet --depth 1 --branch "$(3)" "$(2)" "$(1)"; \
		fi; \
	else \
		git clone --quiet --depth 1 --branch "$(3)" "$(2)" "$(1)"; \
	fi
endef


# --------------------------------------------------------------------
# ACME Permissions Helper
# --------------------------------------------------------------------
define acme_fix_perms
	$(run_as_root) sh -c '\
		chown -R $(ROOT_UID):$(ROOT_GID) "$(1)"; \
		find "$(1)" -type d -exec chmod 0700 {} +; \
		find "$(1)" -type f -name "*.sh" -exec chmod 0755 {} +; \
		find "$(1)" -type f ! -name "*.sh" -exec chmod 0600 {} +; \
	'
endef


# ====================================================================
# APT Management Macros
# ====================================================================

# --------------------------------------------------------------------
# apt_install — install a single package if missing
# --------------------------------------------------------------------
define apt_install
	@command -v $(1) >/dev/null 2>&1 || { \
		echo "apt 📦 Installing $(2)..."; \
		$(call apt_update_if_needed); \
		$(run_as_root) sh -c '( test -x /usr/local/sbin/apt-proxy-auto.sh && /usr/local/sbin/apt-proxy-auto.sh ) || true'; \
		$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
			-o Dpkg::Options::="--force-confold" \
			-o Dpkg::Options::="--force-confdef" $(2); \
	}
endef


# --------------------------------------------------------------------
# apt_remove — remove installed packages in one resolver pass
# --------------------------------------------------------------------
define apt_remove
	PKGS="$(1)"; \
	if [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "🗑️ Removing apt packages: $$PKGS"; \
	fi; \
	INSTALLED=$$( \
		dpkg-query -W -f='$${Status} $${Package}\n' $$PKGS 2>/dev/null || true \
		| awk -F'\t' '$$1 == "install ok installed" {print $$2}' \
	); \
	if [ -z "$$INSTALLED" ]; then \
		[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "ℹ️ No packages to remove"; \
		exit 0; \
	fi; \
	[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "ℹ️ Installed packages to remove: $$INSTALLED"; \
	DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get remove -y --allow-change-held-packages $$INSTALLED >/dev/null 2>&1
endef


# --------------------------------------------------------------------
# apt_update_if_needed — update apt cache only if stale
# --------------------------------------------------------------------
define apt_update_if_needed
	$(run_as_root) sh -c 'test $$(find /var/lib/apt/lists -mmin -60 | grep -q .) || apt-get update -qq'
endef


# --------------------------------------------------------------------
# apt_install_group — install multiple packages in one resolver pass
# --------------------------------------------------------------------
define apt_install_group
	PKGS="$(1)"; \
	[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "📦 Installing apt package group: $$PKGS"; \
	MISSING=$$( \
		for pkg in $$PKGS; do \
			if ! dpkg-query -W -f='$${Status}' "$$pkg" 2>/dev/null | grep -q "ok installed"; then \
				echo "$$pkg"; \
			fi; \
		done \
	); \
	if [ -z "$$MISSING" ]; then \
		[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "ℹ️ core apt group already satisfied"; \
		exit 0; \
	fi; \
	[ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ] && echo "ℹ️ Missing packages: $$MISSING"; \
	DEBIAN_FRONTEND=noninteractive $(run_as_root) apt-get install -y --no-install-recommends $$MISSING
endef


# --------------------------------------------------------------------
# ensure_service_enabled — enable systemd service if not already enabled
# --------------------------------------------------------------------
define ensure_service_enabled
	if ! systemctl is-enabled $(1) >/dev/null 2>&1; then \
		$(run_as_root) systemctl enable --now $(1) >/dev/null 2>&1 || true; \
		echo "✅ $(2) enabled"; \
	elif [ -n "$(VERBOSE)" ] && [ "$(VERBOSE)" != "0" ]; then \
		echo "ℹ️ $(2) already enabled"; \
	fi
endef


# ====================================================================
# Tmpfile Helpers
# ====================================================================
define TMPFILE_BLOCK
	@trap 'rm -f "$(1)"' EXIT; \
	{ \
		$(2) \
	}
endef


# ====================================================================
# Diagnostics
# ====================================================================
.PHONY: apt-diagnostic
apt-diagnostic:
	@echo "=== PACKAGE ORIGIN DIAGNOSTIC ==="; \
	for p in $(UGOS_VENDOR_PACKAGES) $(APT_INSTALLABLE_PACKAGES); do \
		printf "%-25s : " $$p; \
		if dpkg-query -W -f='$${Status}\n' $$p 2>/dev/null | grep -q "^install ok installed$$"; then \
			PRIO=$$(dpkg-query -W -f='$${Priority}\n' $$p 2>/dev/null || echo "unknown"); \
			ESS=$$(dpkg-query -W -f='$${Essential}\n' $$p 2>/dev/null || echo "no"); \
			if [ "$$ESS" = "yes" ]; then \
				echo "UGOS (essential)"; \
			elif [ "$$PRIO" = "required" ]; then \
				echo "UGOS (priority: required)"; \
			else \
				echo "USER-INSTALLED (removable)"; \
			fi; \
		else \
			echo "NOT INSTALLED"; \
		fi; \
	done


# --------------------------------------------------------------------
# apt-uninstall-installed — best-effort removal of homelab packages
# --------------------------------------------------------------------
.PHONY: apt-uninstall-installed
apt-uninstall-installed: | $(run_as_root)
	@echo "🗑️  Removing all homelab APT packages (best-effort)..."
	@for pkg in $(APT_INSTALLABLE_PACKAGES); do \
		BIN=$$(command -v "$$pkg" 2>/dev/null || true); \
		if [ -n "$$BIN" ]; then \
			REAL=$$(dpkg -S "$$BIN" 2>/dev/null | head -n1 | cut -d: -f1); \
		else \
			REAL="$$pkg"; \
		fi; \
		[ -z "$$REAL" ] && REAL="$$pkg"; \
		printf "📦 Removing %-25s (pkg: %-20s) ... " "$$pkg" "$$REAL"; \
		if $(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$$REAL" >/dev/null 2>&1; then \
			echo "OK ✅"; \
		else \
			echo "not installed or failed"; \
		fi; \
	done; \
	echo " Autoremoving leftover dependencies"; \
	$(run_as_root) env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true; \
	echo "🔍 Done."
