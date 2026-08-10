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
    apt-cacher-ng-setup \
    apt-cacher-ng-enable-https \
    apt-proxy-auto-enable

apt-cacher-ng-setup:
	@$(run_as_root) sh -eu -c '\
		if [ ! -d /tank ]; then \
			echo "ℹ️ /tank not found; skipping ZFS cache relocation"; \
			exit 0; \
		fi; \
		if [ ! -f /etc/apt-cacher-ng/acng.conf ]; then \
			echo "ℹ️ apt-cacher-ng not installed; skipping storage setup"; \
			exit 0; \
		fi; \
		APT_USER=$$(getent passwd apt-cacher-ng >/dev/null 2>&1 && echo apt-cacher-ng || (getent passwd apt-cng >/dev/null 2>&1 && echo apt-cng || (getent passwd apt-cacher >/dev/null 2>&1 && echo apt-cacher || echo root))); \
		echo "🔧 Setting up apt-cacher-ng storage on /tank (user: $${APT_USER})"; \
		systemctl stop apt-cacher-ng || true; \
		mkdir -p /tank/cache/apt-cacher-ng /tank/cache/apt-cacher-ng/_xstore /tank/log/apt-cacher-ng; \
		if [ ! -L /var/cache/apt-cacher-ng ]; then \
			if [ -d /var/cache/apt-cacher-ng ]; then \
				rsync -av --exclude="_xstore" /var/cache/apt-cacher-ng/ /tank/cache/apt-cacher-ng/; \
				rm -rf /var/cache/apt-cacher-ng; \
			fi; \
			ln -s /tank/cache/apt-cacher-ng /var/cache/apt-cacher-ng; \
		fi; \
		if [ -L /var/log/apt-cacher-ng ]; then \
			rm -f /var/log/apt-cacher-ng; \
		fi; \
		if [ -d /var/log/apt-cacher-ng ] && [ ! -L /var/log/apt-cacher-ng ]; then \
			cp -a /var/log/apt-cacher-ng/. /tank/log/apt-cacher-ng/ 2>/dev/null || true; \
			rm -rf /var/log/apt-cacher-ng; \
		fi; \
		ln -s /tank/log/apt-cacher-ng /var/log/apt-cacher-ng; \
		chown -h "$${APT_USER}:$${APT_USER}" /var/cache/apt-cacher-ng /var/log/apt-cacher-ng 2>/dev/null || true; \
		chown -R "$${APT_USER}:$${APT_USER}" /tank/cache/apt-cacher-ng /tank/log/apt-cacher-ng; \
		find /tank/log/apt-cacher-ng -type f -exec chmod 664 {} + 2>/dev/null || true; \
		find /tank/cache/apt-cacher-ng -type f -exec chmod 664 {} + 2>/dev/null || true; \
		find /tank/log/apt-cacher-ng -type d -exec chmod 775 {} + 2>/dev/null || true; \
		find /tank/cache/apt-cacher-ng -type d -exec chmod 775 {} + 2>/dev/null || true; \
		if [ -d /etc/apparmor.d ] && [ -f /etc/apparmor.d/usr.sbin.apt-cacher-ng ]; then \
			echo "🛡️ Configuring AppArmor local profile for /tank/log and /tank/cache"; \
			mkdir -p /etc/apparmor.d/local; \
			printf "%s\n" \
				"# Added by homelab 70_apt_proxy_auto.mk" \
				"/tank/cache/apt-cacher-ng/ r," \
				"/tank/cache/apt-cacher-ng/** rwk," \
				"/tank/log/apt-cacher-ng/ r," \
				"/tank/log/apt-cacher-ng/** rwk," \
				> /etc/apparmor.d/local/usr.sbin.apt-cacher-ng; \
			apparmor_parser -r /etc/apparmor.d/usr.sbin.apt-cacher-ng 2>/dev/null || systemctl reload apparmor || true; \
		fi; \
		echo "🔧 Removing systemd TasksMax limitations"; \
		mkdir -p /etc/systemd/system/apt-cacher-ng.service.d; \
		printf "[Service]\nTasksMax=infinity\nLimitNOFILE=65536\n" > /etc/systemd/system/apt-cacher-ng.service.d/limits.conf; \
		systemctl daemon-reload; \
		restorecon -R /var/cache/apt-cacher-ng /var/log/apt-cacher-ng /tank/cache/apt-cacher-ng /tank/log/apt-cacher-ng 2>/dev/null || true'

apt-cacher-ng-enable-https: apt-cacher-ng-setup
	@$(run_as_root) sh -eu -c '\
		if [ ! -f /etc/apt-cacher-ng/acng.conf ]; then \
			echo "ℹ️ apt-cacher-ng not found or config missing; skipping server-side tweak"; \
			exit 0; \
		fi; \
		APT_USER=$$(getent passwd apt-cacher-ng >/dev/null 2>&1 && echo apt-cacher-ng || (getent passwd apt-cng >/dev/null 2>&1 && echo apt-cng || (getent passwd apt-cacher >/dev/null 2>&1 && echo apt-cacher || echo root))); \
		mkdir -p /tank/cache/apt-cacher-ng /tank/log/apt-cacher-ng; \
		if [ -L /var/log/apt-cacher-ng ]; then \
			rm -f /var/log/apt-cacher-ng; \
		fi; \
		if [ -d /var/log/apt-cacher-ng ] && [ ! -L /var/log/apt-cacher-ng ]; then \
			cp -a /var/log/apt-cacher-ng/. /tank/log/apt-cacher-ng/ 2>/dev/null || true; \
			rm -rf /var/log/apt-cacher-ng; \
		fi; \
		ln -s /tank/log/apt-cacher-ng /var/log/apt-cacher-ng; \
		chown -h "$${APT_USER}:$${APT_USER}" /var/cache/apt-cacher-ng /var/log/apt-cacher-ng 2>/dev/null || true; \
		chown -R "$${APT_USER}:$${APT_USER}" /tank/cache/apt-cacher-ng /tank/log/apt-cacher-ng; \
		find /tank/log/apt-cacher-ng -type f -exec chmod 664 {} + 2>/dev/null || true; \
		find /tank/cache/apt-cacher-ng -type f -exec chmod 664 {} + 2>/dev/null || true; \
		find /tank/log/apt-cacher-ng -type d -exec chmod 775 {} + 2>/dev/null || true; \
		find /tank/cache/apt-cacher-ng -type d -exec chmod 775 {} + 2>/dev/null || true; \
		restorecon -R /var/cache/apt-cacher-ng /var/log/apt-cacher-ng /tank/cache/apt-cacher-ng /tank/log/apt-cacher-ng 2>/dev/null || true; \
		systemctl reset-failed apt-cacher-ng.service || true; \
		if ! systemctl restart apt-cacher-ng; then \
			echo "❌ apt-cacher-ng failed to start. Printing journal logs:"; \
			journalctl -u apt-cacher-ng.service -n 30 --no-pager; \
			exit 1; \
		fi; \
		echo "🔄 Restarted apt-cacher-ng successfully"'

apt-proxy-auto-install: apt-cacher-ng-enable-https $(INSTALL_FILE_IF_CHANGED)
	@set -eu; \
	changed=0; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_SERVICE_SRC)" "" "" "$(APT_PROXY_AUTO_SERVICE_DST)" "root" "root" "0644" && true || \
		{ [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && changed=1 || exit $$?; }; \
	$(run_as_root) env CHANGED_EXIT_CODE=$(INSTALL_IF_CHANGED_EXIT_CHANGED) \
		$(INSTALL_FILE_IF_CHANGED) -q "" "" "$(APT_PROXY_AUTO_TIMER_SRC)" "" "" "$(APT_PROXY_AUTO_TIMER_DST)" "root" "root" "0644" && true || \
		{ [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ] && changed=1 || exit $$?; }; \
	$(run_as_root) sh -eu -c '\
		mkdir -p /usr/local/sbin; \
		if ! grep -q "pkgs.netbird.io" /etc/hosts; then \
			echo "🔧 Adding IPv4 override for pkgs.netbird.io in /etc/hosts"; \
			printf "%s\n" "5.22.212.152 pkgs.netbird.io" >> /etc/hosts; \
		fi; \
		if [ -f /etc/apt-cacher-ng/acng.conf ]; then \
			printf "%s\n" \
				"#!/bin/sh" \
				"set -eu" \
				"systemctl enable --now apt-cacher-ng >/dev/null 2>&1 || true" \
				"echo '\''Acquire::http::Proxy \"http://127.0.0.1:3142\";'\'' > /etc/apt/apt.conf.d/01proxy" \
				"echo '\''Acquire::https::Proxy \"DIRECT\";'\'' >> /etc/apt/apt.conf.d/01proxy" \
				"rm -f /etc/apt/apt.conf.d/01proxy.conf" \
				"echo '\''apt-proxy-auto: ENABLED (http://127.0.0.1:3142)'\''" \
				> $(APT_PROXY_AUTO); \
		else \
			printf "%s\n" \
				"#!/bin/sh" \
				"set -eu" \
				"if nc -z -w 2 10.89.12.4 3142 2>/dev/null; then" \
				"    echo '\''Acquire::http::Proxy \"http://10.89.12.4:3142\";'\'' > /etc/apt/apt.conf.d/01proxy" \
				"    echo '\''Acquire::https::Proxy \"DIRECT\";'\'' >> /etc/apt/apt.conf.d/01proxy" \
				"    echo '\''apt-proxy-auto: ENABLED (http://10.89.12.4:3142)'\''" \
				"    exit 0" \
				"fi" \
				"rm -f /etc/apt/apt.conf.d/01proxy" \
				"echo '\''apt-proxy-auto: DISABLED (no proxy reachable)'\''" \
				> $(APT_PROXY_AUTO); \
		fi; \
		chmod 0755 $(APT_PROXY_AUTO)'; \
	if [ "$$changed" -eq 1 ]; then \
		echo "🔄 Unit files updated, reloading systemd"; \
		$(run_as_root) systemctl daemon-reload; \
	fi; \
	test -z "$(VERBOSE)" || echo "✅ apt-proxy-auto installed"

apt-proxy-auto-enable: apt-proxy-auto-install
	@$(run_as_root) sh -eu -c '\
		systemctl enable --now apt-proxy-auto.timer; \
		"$(APT_PROXY_AUTO)"'

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