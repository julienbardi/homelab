# ============================================================
# mk/70_apt_proxy_auto.mk — client-side APT proxy auto-toggle
# ============================================================

APT_PROXY_AUTO := /usr/local/sbin/apt-proxy-auto.sh

APT_PROXY_AUTO_SERVICE_SRC := $(REPO_ROOT)/config/systemd/apt-proxy-auto.service
APT_PROXY_AUTO_TIMER_SRC   := $(REPO_ROOT)/config/systemd/apt-proxy-auto.timer

APT_PROXY_AUTO_SERVICE_DST := /etc/systemd/system/apt-proxy-auto.service
APT_PROXY_AUTO_TIMER_DST   := /etc/systemd/system/apt-proxy-auto.timer

ifndef INSTALL_FILE_IF_CHANGED
$(error INSTALL_FILE_IF_CHANGED not defined)
endif

ifndef run_as_root
$(error run_as_root  not defined)
endif

.PHONY: \
	make \
	apt-proxy-auto-disable \
	apt-proxy-auto-status \
	apt-proxy-auto-install \
	apt-cacher-ng-enable-https \
	apt-proxy-auto-enable

apt-cacher-ng-enable-https: ensure-run-as-root
	@$(run_as_root) sh -c '\
		if [ ! -f /etc/apt-cacher-ng/acng.conf ]; then \
			echo "ℹ️ apt-cacher-ng not found or config missing; skipping server-side tweak"; \
		elif grep -Fq "# == inserted by 70_apt_proxy_auto.mk" /etc/apt-cacher-ng/acng.conf; then \
			test -z "$(VERBOSE)" || echo "ℹ️ apt-cacher-ng HTTPS passthrough section already present"; \
		else \
			test -z "$(VERBOSE)" || echo "🔧 Inserting apt-cacher-ng HTTPS passthrough section"; \
			printf "%s\n" "" "# == inserted by 70_apt_proxy_auto.mk ========================" "# Allow HTTPS CONNECT tunneling for modern APT" "PassThroughPattern: .*" "# ============================================================" >> /etc/apt-cacher-ng/acng.conf; \
			if grep -Fq "# == inserted by 70_apt_proxy_auto.mk" /etc/apt-cacher-ng/acng.conf; then \
				if systemctl list-unit-files | grep -q "^apt-cacher-ng"; then \
					systemctl restart apt-cacher-ng && echo "🔄 Inserted passthrough and restarted apt-cacher-ng"; \
				else \
					echo "🔄 Inserted passthrough (apt-cacher-ng unit not present; skipping restart)"; \
				fi; \
			else \
				echo "❌ Failed to insert HTTPS passthrough block" >&2; exit 1; \
			fi; \
		fi'

apt-proxy-auto-install: ensure-run-as-root $(INSTALL_FILE_IF_CHANGED)
	@set -eu; \
	rc=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_SERVICE_SRC)" "" "" "$(APT_PROXY_AUTO_SERVICE_DST)" "root" "root" "0644" || rc=$$?; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_TIMER_SRC)" "" "" "$(APT_PROXY_AUTO_TIMER_DST)" "root" "root" "0644" || rc=$$?; \
	if [ "$$rc" -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]; then \
		echo "🔄 Unit files updated, reloading systemd"; \
		$(run_as_root) systemctl daemon-reload; \
	else \
		[ "$$rc" -eq 0 ] || exit "$$rc"; \
	fi; \
	test -z "$(VERBOSE)" || echo "✅ apt-proxy-auto installed"

apt-proxy-auto-enable: apt-cacher-ng-enable-https apt-proxy-auto-install ensure-run-as-root
	@# Only run the runtime sync if the timer was just enabled or proxy absent
	@$(run_as_root) sh -c '\
		was_enabled=0; \
		if systemctl is-enabled --quiet apt-proxy-auto.timer; then was_enabled=1; fi; \
		systemctl enable --now apt-proxy-auto.timer; \
		if [ "$$was_enabled" -eq 0 ] || [ ! -f /etc/apt/apt.conf.d/01proxy ]; then \
			echo "🚀 Running apt-proxy-auto once (immediate sync)"; \
			"$(APT_PROXY_AUTO)"; \
		else \
			test -z "$(VERBOSE)" || echo "ℹ️ apt-proxy-auto already enabled and proxy present; skipping immediate run"; \
		fi'

apt-proxy-auto-disable: ensure-run-as-root
	@$(run_as_root) systemctl disable --now apt-proxy-auto.timer || true
	@$(run_as_root) rm -f /etc/apt/apt.conf.d/01proxy
	@echo "✅ apt-proxy-auto timer disabled and proxy file removed"

apt-proxy-auto-status: ensure-run-as-root
	@echo "🔍 apt-proxy-auto status"
	@$(run_as_root) systemctl is-active --quiet apt-proxy-auto.timer || \
		( echo "❌ apt-proxy-auto.timer not active"; exit 1 )
	@echo "📄 Current APT proxy config (/etc/apt/apt.conf.d/01proxy):"
	@$(run_as_root) sh -c 'test -f /etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy || echo "(absent -> direct mirrors)"'
