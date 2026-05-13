WATCHDOG_UNIT_SRC := $(REPO_ROOT)/config/systemd/router-prefix-watchdog.service.in
WATCHDOG_UNIT_DST := /etc/systemd/system/router-prefix-watchdog.service

install-router-prefix-watchdog: | ensure-run-as-root
	@echo "🛠️ Installing router-prefix-watchdog service"
	@tmp=$$(mktemp); \
	sed \
		-e "s|@OPERATOR_USER@|$(OPERATOR_USER)|g" \
		-e "s|@PRIMARY_ADMIN_GROUP@|$(PRIMARY_ADMIN_GROUP)|g" \
		-e "s|@REPO_ROOT@|$(REPO_ROOT)|g" \
		-e "s|@INSTALL_PATH@|$(INSTALL_PATH)|g" \
		"$(WATCHDOG_UNIT_SRC)" > "$$tmp"; \
	$(run_as_root) sh -c '\
		status=0; \
		changed=0; \
		tmpfile="'"$$tmp"'"; \
		real_tmp=$$(mktemp -p /run homelab.watchdog.XXXXXX); \
		chown $(OPERATOR_USER):$(PRIMARY_ADMIN_GROUP) "$$real_tmp"; \
		cat "$$tmpfile" > "$$real_tmp"; \
		$(INSTALL_FILE_IF_CHANGED) -q \
			"" "" "$$real_tmp" \
			"" "" "$(WATCHDOG_UNIT_DST)" \
			"$(ROOT_UID)" "$(ROOT_GID)" "0644" || status=$$?; \
		if [ $$status -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then changed=1; fi; \
		rm -f "$$real_tmp"; \
		if [ $$changed -eq 1 ]; then \
			systemctl daemon-reload; \
			systemctl enable --now router-prefix-watchdog.service; \
		else \
			if ! systemctl is-enabled router-prefix-watchdog.service >/dev/null 2>&1; then \
				systemctl enable --now router-prefix-watchdog.service; \
			fi; \
		fi; \
		exit $$status \
	'; \
	status=$$?; \
	rm -f "$$tmp"; \
	if [ $$status -ne 0 ] && [ $$status -ne $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "❌ IFC fatal error (exit $$status) installing watchdog unit"; \
		exit $$status; \
	fi; \
	echo "🟢 router-prefix-watchdog active"
