# 90_systemd.mk — Systemd unit management for homelab services

# ------------------------------------------------------------
# Per‑unit installers (explicit, privilege‑correct)
# ------------------------------------------------------------

.PHONY: install-dns-health
install-dns-health:
	@$(run_as_root) install -m 0644 -o $(ROOT_UID) -g $(ROOT_GID) \
		$(REPO_SYSTEMD)/homelab-dns-health.service \
		$(SYSTEMD_DIR)/homelab-dns-health.service

.PHONY: install-nas-prefix-watchdog
install-nas-prefix-watchdog:
	@$(run_as_root) sh -c '\
		# --- NAS IPv6 prefix watchdog --- \
		rc="$$( \
			$(INSTALL_FILES_IF_CHANGED) RC \
				"" "" "$(REPO_ROOT)/scripts/homelab-prefix-converge.sh" \
				"" "" "/usr/local/bin/homelab-prefix-converge.sh" \
				"$(ROOT_UID)" "$(ROOT_GID)" "0755" \
				"" "" "$(REPO_ROOT)/config/systemd/homelab-prefix-converge.service" \
				"" "" "/etc/systemd/system/homelab-prefix-converge.service" \
				"$(ROOT_UID)" "$(ROOT_GID)" "0644" \
				"" "" "$(REPO_ROOT)/config/systemd/homelab-prefix-converge.timer" \
				"" "" "/etc/systemd/system/homelab-prefix-converge.timer" \
				"$(ROOT_UID)" "$(ROOT_GID)" "0644" \
			; printf "%d" $$? \
		)"; \
		if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
			systemctl daemon-reload; \
			systemctl enable --now homelab-prefix-converge.timer; \
		elif [ "$$rc" -ne $(INSTALL_IF_CHANGED_EXIT_UNCHANGED) ]; then \
			exit "$$rc"; \
		fi \
	'

.PHONY: install-nas-prefix-watchdog-v1
install-nas-prefix-watchdog-v1:
	@echo "🔧 Installing NAS IPv6 prefix watchdog"
	@$(run_as_root) sh -c "\
		set -e; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 755 \"$(REPO_ROOT)/scripts/homelab-prefix-converge.sh\" /usr/local/bin/; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 644 \"$(REPO_ROOT)/config/systemd/homelab-prefix-converge.service\" /etc/systemd/system/; \
		install -o $(ROOT_UID) -g $(ROOT_GID) -m 644 \"$(REPO_ROOT)/config/systemd/homelab-prefix-converge.timer\" /etc/systemd/system/; \
		systemctl daemon-reload; \
		systemctl enable --now homelab-prefix-converge.timer \
	"

# ------------------------------------------------------------
# Umbrella systemd installer
# ------------------------------------------------------------

.PHONY: install-systemd enable-systemd verify-systemd uninstall-systemd

install-systemd: install-dns-health install-infomaniak-ddns
	@$(run_as_root) sh -c '\
		# --- fix vendor-broken index_serv.service --- \
		mkdir -p "$(SYSTEMD_DIR)/index_serv.service.d"; \
		rc="$$( \
			$(INSTALL_FILE_IF_CHANGED) \
				"" "" "$(REPO_SYSTEMD)/index_serv.service.d/10-fix-output.conf" \
				"" "" "$(SYSTEMD_DIR)/index_serv.service.d/10-fix-output.conf" \
				"$(ROOT_UID)" "$(ROOT_GID)" "0644"; \
			printf "%d" $$? \
		)"; \
		if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
			systemctl daemon-reload; \
		elif [ "$$rc" -ne $(INSTALL_IF_CHANGED_EXIT_UNCHANGED) ]; then \
			exit "$$rc"; \
		fi \
	'

# ------------------------------------------------------------
# Enable + start services
# ------------------------------------------------------------

enable-systemd: install-systemd
	@$(run_as_root) sh -c '\
		if systemctl is-active --quiet homelab-unbound.service; then \
			echo "🟢 homelab-unbound.service already running and converged"; \
		else \
			echo "🚀 Starting homelab-unbound.service (was not active)"; \
			systemctl start homelab-unbound.service || true; \
		fi; \
	'

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

verify-systemd:
	@$(run_as_root) systemctl status unbound --no-pager || true

# ------------------------------------------------------------
# Uninstall (minimal)
# ------------------------------------------------------------

uninstall-systemd:
	$(run_as_root) systemctl daemon-reload

.PHONY: clean
clean:
	@$(run_as_root) sh -c '\
		echo " Removing tailscaled role units"; \
		systemctl disable tailscaled-lan.service >/dev/null 2>&1 || true; \
		rm -f /etc/systemd/system/tailscaled-lan.service || true; \
		systemctl daemon-reload >/dev/null 2>&1; \
		echo "✅ Cleaned tailscaled units and disabled services"; \
	'

.PHONY: reload
reload:
	@$(run_as_root) sh -c '\
		echo "🔄 Reloading systemd units"; \
		systemctl daemon-reload; \
		echo "✅ systemd reloaded"; \
	'

.PHONY: restart
restart:
	@$(run_as_root) sh -c '\
		echo "🔄 Restarting tailscaled services"; \
		systemctl restart tailscaled >/dev/null 2>&1 || true; \
		systemctl restart tailscaled-lan.service >/dev/null 2>&1 || true; \
		echo "✅ tailscaled services restarted"; \
	'

# ============================================================================
# Infomaniak IPv6 DynDNS
# ============================================================================

DDNS_SERVICE_SRC := $(REPO_ROOT)/config/systemd/homelab-infomaniak-ddns.service.in
DDNS_SERVICE_DST := /etc/systemd/system/homelab-infomaniak-ddns.service

DDNS_TIMER_SRC := $(REPO_ROOT)/config/systemd/homelab-infomaniak-ddns.timer.in
DDNS_TIMER_DST := /etc/systemd/system/homelab-infomaniak-ddns.timer

.PHONY: install-infomaniak-ddns
install-infomaniak-ddns: \
	ddns-runtime \
	ensure-state-dirs \
	$(INSTALL_PATH)/homelab-infomaniak-ddns.sh
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛠️ Installing Infomaniak DDNS services" || true; fi; \
	CHANGED=0; \
	\
	tmp="$$(umask 077 && mktemp -p "$(RUNTIME_DIR)" tmp.ddns.service.XXXXXX)"; \
	ROOT_UID="$(ROOT_UID)" \
	ROOT_GID="$(ROOT_GID)" \
	REPO_ROOT="$(REPO_ROOT)" \
	INSTALL_PATH="$(INSTALL_PATH)" \
	envsubst < "$(DDNS_SERVICE_SRC)" > "$$tmp"; \
	\
	IFC_STATUS=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$$tmp" \
		"" "" "$(DDNS_SERVICE_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || IFC_STATUS=$$?; \
	rm -f "$$tmp"; \
	\
	if [ $$IFC_STATUS -ne 0 ] && [ $$IFC_STATUS -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ IFC: Fatal error installing homelab-infomaniak-ddns.service"; \
		exit $$IFC_STATUS; \
	fi; \
	\
	if [ $$IFC_STATUS -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		CHANGED=1; \
	fi; \
	\
	tmp="$$(umask 077 && mktemp -p "$(RUNTIME_DIR)" tmp.ddns.timer.XXXXXX)"; \
	ROOT_UID="$(ROOT_UID)" \
	ROOT_GID="$(ROOT_GID)" \
	REPO_ROOT="$(REPO_ROOT)" \
	INSTALL_PATH="$(INSTALL_PATH)" \
	envsubst < "$(DDNS_TIMER_SRC)" > "$$tmp"; \
	\
	IFC_STATUS=0; \
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$$tmp" \
		"" "" "$(DDNS_TIMER_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644" || IFC_STATUS=$$?; \
	rm -f "$$tmp"; \
	\
	if [ $$IFC_STATUS -ne 0 ] && [ $$IFC_STATUS -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ IFC: Fatal error installing homelab-infomaniak-ddns.timer"; \
		exit $$IFC_STATUS; \
	fi; \
	\
	if [ $$IFC_STATUS -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		CHANGED=1; \
	fi; \
	\
	if [ $$CHANGED -eq 1 ]; then \
		$(run_as_root) systemctl daemon-reload; \
	fi; \
	\
	if ! systemctl is-enabled homelab-infomaniak-ddns.timer >/dev/null 2>&1; then \
		$(run_as_root) systemctl enable --now homelab-infomaniak-ddns.timer; \
	else \
		    $(run_as_root) systemctl start homelab-infomaniak-ddns.timer >/dev/null 2>&1 || true; \
	fi; \
	\
	if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 Infomaniak DDNS timer active" || true; fi

.PHONY: ddns-now
ddns-now:
	@$(run_as_root) systemctl start homelab-infomaniak-ddns.service