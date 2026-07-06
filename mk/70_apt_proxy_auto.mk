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
$(error run_as_root not defined)
endif

.PHONY: \
	apt-proxy-auto-disable \
	apt-proxy-auto-status \
	apt-proxy-auto-install \
	apt-cacher-ng-enable-https \
	apt-proxy-auto-enable

apt-cacher-ng-enable-https:
	@$(run_as_root) sh -eu -c '\
		if [ ! -f /etc/apt-cacher-ng/acng.conf ]; then \
			echo "ℹ️ apt-cacher-ng not found or config missing; skipping server-side tweak"; \
			exit 0; \
		fi; \
		if grep -Fq "# == inserted by 70_apt_proxy_auto.mk" /etc/apt-cacher-ng/acng.conf; then \
			test -z "$(VERBOSE)" || echo "ℹ️ HTTPS passthrough already present"; \
			exit 0; \
		fi; \
		test -z "$(VERBOSE)" || echo "🔧 Inserting HTTPS passthrough section"; \
		printf "%s\n" "" \
			"# == inserted by 70_apt_proxy_auto.mk ========================" \
			"# Allow HTTPS CONNECT tunneling for modern APT" \
			"PassThroughPattern: .*" \
			"# ============================================================" \
			>> /etc/apt-cacher-ng/acng.conf; \
		if systemctl list-unit-files | grep -q "^apt-cacher-ng"; then \
			systemctl restart apt-cacher-ng && echo "🔄 Restarted apt-cacher-ng"; \
		else \
			echo "ℹ️ Unit not present; skipping restart"; \
		fi'

apt-proxy-auto-install: $(INSTALL_FILE_IF_CHANGED)
	@set -eu; \
	changed=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_SERVICE_SRC)" "" "" "$(APT_PROXY_AUTO_SERVICE_DST)" "root" "root" "0644" && true || \
		{ [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && changed=1 || exit $$?; }; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_TIMER_SRC)" "" "" "$(APT_PROXY_AUTO_TIMER_DST)" "root" "root" "0644" && true || \
		{ [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && changed=1 || exit $$?; }; \
	if [ "$$changed" -eq 1 ]; then \
		echo "🔄 Unit files updated, reloading systemd"; \
		$(run_as_root) systemctl daemon-reload; \
	fi; \
	test -z "$(VERBOSE)" || echo "✅ apt-proxy-auto installed"

apt-proxy-auto-enable: apt-cacher-ng-enable-https apt-proxy-auto-install
	@$(run_as_root) sh -eu -c '\
		was_enabled=0; \
		systemctl is-enabled --quiet apt-proxy-auto.timer && was_enabled=1 || true; \
		systemctl enable --now apt-proxy-auto.timer; \
		if [ "$$was_enabled" -eq 0 ] || [ ! -f /etc/apt/apt.conf.d/01proxy ]; then \
			echo "🚀 Running apt-proxy-auto once (immediate sync)"; \
			"$(APT_PROXY_AUTO)"; \
		else \
			test -z "$(VERBOSE)" || echo "ℹ️ Timer already enabled and proxy present; skipping immediate run"; \
		fi'

apt-proxy-auto-disable:
	@$(run_as_root) systemctl disable --now apt-proxy-auto.timer || true
	@$(run_as_root) rm -f /etc/apt/apt.conf.d/01proxy
	@echo "✅ apt-proxy-auto timer disabled and proxy file removed"

apt-proxy-auto-status:
	@echo "🔍 apt-proxy-auto status"
	@$(run_as_root) systemctl is-active --quiet apt-proxy-auto.timer || \
		( echo "❌ apt-proxy-auto.timer not active"; exit 1 )
	@echo "📋 Current APT proxy config (/etc/apt/apt.conf.d/01proxy):"
	@$(run_as_root) sh -c 'test -f /etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy || echo "(absent -> direct mirrors)"'
