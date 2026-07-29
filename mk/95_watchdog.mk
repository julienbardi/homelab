# mk/95_watchdog.mk
# Router Prefix Watchdog

WATCHDOG_UNIT_SRC := $(REPO_ROOT)/config/systemd/router-prefix-watchdog.service.in
WATCHDOG_UNIT_DST := /etc/systemd/system/router-prefix-watchdog.service

install-router-prefix-watchdog:
	@[ -n "$(VERBOSE)" ] && echo "🛠️ Installing router-prefix-watchdog service" || true; \
	tmp=$$(mktemp /run/homelab.watchdog.XXXXXX); \
	OPERATOR_USER="$(OPERATOR_USER)" \
	PRIMARY_ADMIN_GROUP="$(PRIMARY_ADMIN_GROUP)" \
	REPO_ROOT="$(REPO_ROOT)" \
	INSTALL_PATH="$(INSTALL_PATH)" \
	envsubst < "$(WATCHDOG_UNIT_SRC)" > "$$tmp"; \
	\
	status=$$( $(run_as_root) $(INSTALL_FILE_IF_CHANGED) -q \
		"" "" "$$tmp" \
		"" "" "$(WATCHDOG_UNIT_DST)" \
		"$(ROOT_UID)" "$(ROOT_GID)" "0644"; echo $$? ); \
	rm -f "$$tmp"; \
	\
	if [ $$status -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) systemctl enable --now router-prefix-watchdog.service; \
	else \
		if ! systemctl is-enabled router-prefix-watchdog.service >/dev/null 2>&1; then \
			$(run_as_root) systemctl enable --now router-prefix-watchdog.service; \
		fi; \
	fi; \
	\
	[ -n "$(VERBOSE)" ] && echo "🟢 router-prefix-watchdog active" || true
