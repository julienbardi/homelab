# mk/95_watchdog.mk
# Router Prefix Watchdog

WATCHDOG_UNIT_SRC := $(REPO_ROOT)/config/systemd/router-prefix-watchdog.service.in
WATCHDOG_UNIT_DST := /etc/systemd/system/router-prefix-watchdog.service

install-router-prefix-watchdog:
	@if [ "$(VERBOSE)" -ge 1 ]; then echo "🛠️ Installing router-prefix-watchdog service" || true; fi; \
	tmp=$$(mktemp /run/homelab.watchdog.XXXXXX); \
	ROOT_UID="$(ROOT_UID)" \
	ROOT_GID="$(ROOT_GID)" \
	REPO_ROOT="$(REPO_ROOT)" \
	INSTALL_PATH="$(INSTALL_PATH)" \
	envsubst < "$(WATCHDOG_UNIT_SRC)" > "$$tmp"; \
	\
	$(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$$tmp" \
		"" "" "$(WATCHDOG_UNIT_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644"; \
	IFC_STATUS=$$?; \
	rm -f "$$tmp"; \
	# Fatal on IFC failure \
	if [ $$IFC_STATUS -ne 0 ] && [ $$IFC_STATUS -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ IFC: Fatal error (exit $$IFC_STATUS) installing router-prefix-watchdog.service"; \
		exit $$IFC_STATUS; \
	fi; \
	\
	# Normal success path \
	if [ $$IFC_STATUS -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable --now router-prefix-watchdog.service; \
	else \
		if ! systemctl is-enabled router-prefix-watchdog.service >/dev/null 2>&1; then \
			$(run_as_root) systemctl enable --now router-prefix-watchdog.service; \
		fi; \
	fi; \
	\
	if [ "$(VERBOSE)" -ge 1 ]; then echo "🟢 router-prefix-watchdog active" || true; fi
