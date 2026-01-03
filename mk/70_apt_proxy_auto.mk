# ============================================================
# mk/70_apt_proxy_auto.mk — client-side APT proxy auto-toggle
# ============================================================

APT_PROXY_AUTO_SCRIPT_SRC := $(HOMELAB_DIR)/scripts/client/apt-proxy-auto.sh
APT_PROXY_AUTO_SCRIPT_DST := /usr/local/sbin/apt-proxy-auto

APT_PROXY_AUTO_SERVICE_SRC := $(HOMELAB_DIR)/config/systemd/apt-proxy-auto.service
APT_PROXY_AUTO_TIMER_SRC   := $(HOMELAB_DIR)/config/systemd/apt-proxy-auto.timer

APT_PROXY_AUTO_SERVICE_DST := /etc/systemd/system/apt-proxy-auto.service
APT_PROXY_AUTO_TIMER_DST   := /etc/systemd/system/apt-proxy-auto.timer

APT_CACHER_NG_HTTPS_BLOCK := \
\# == inserted by 70_apt_proxy_auto.mk ========================\n\
\# Allow HTTPS CONNECT tunneling for modern APT\n\
PassThroughPattern: .*\n\
\# ============================================================\n

.PHONY: \
	apt-cacher-ng-enable-https \
	apt-proxy-auto-install \
	apt-proxy-auto-enable \
	apt-proxy-auto-disable \
	apt-proxy-auto-status
	
apt-cacher-ng-enable-https:
	@echo "🔐 [make] Ensuring apt-cacher-ng allows HTTPS CONNECT"
	@test -f /etc/apt-cacher-ng/acng.conf || { \
		echo "❌ /etc/apt-cacher-ng/acng.conf not found"; \
		exit 1; \
	}
	@if grep -Fq '# == inserted by 70_apt_proxy_auto.mk' /etc/apt-cacher-ng/acng.conf; then \
		echo "ℹ️  HTTPS passthrough section already present"; \
	else \
		echo "➕ Inserting HTTPS passthrough section"; \
		printf "\n$(APT_CACHER_NG_HTTPS_BLOCK)" | \
			$(run_as_root) tee -a /etc/apt-cacher-ng/acng.conf >/dev/null; \
	fi
	@$(run_as_root) systemctl restart apt-cacher-ng
	@echo "✅ [make] apt-cacher-ng HTTPS passthrough ready"

apt-proxy-auto-install:
	@echo "📦 [make] Installing apt-proxy-auto"
	@$(run_as_root) install -m 0755 -o root -g root \
		$(APT_PROXY_AUTO_SCRIPT_SRC) \
		$(APT_PROXY_AUTO_SCRIPT_DST)
	@$(run_as_root) install -m 0644 -o root -g root \
		$(APT_PROXY_AUTO_SERVICE_SRC) \
		$(APT_PROXY_AUTO_SERVICE_DST)
	@$(run_as_root) install -m 0644 -o root -g root \
		$(APT_PROXY_AUTO_TIMER_SRC) \
		$(APT_PROXY_AUTO_TIMER_DST)
	@$(run_as_root) systemctl daemon-reload
	@echo "✅ [make] apt-proxy-auto installed"

apt-proxy-auto-enable: apt-cacher-ng-enable-https apt-proxy-auto-install
	@echo "⏱️  [make] Enabling apt-proxy-auto timer"
	@$(run_as_root) systemctl enable --now apt-proxy-auto.timer
	@$(run_as_root) systemctl is-enabled --quiet apt-proxy-auto.timer || \
		( echo "❌ apt-proxy-auto.timer not enabled"; exit 1 )
	@echo "▶️  [make] Running apt-proxy-auto once (immediate sync)"
	@$(run_as_root) $(APT_PROXY_AUTO_SCRIPT_DST)
	@echo "✅ [make] apt-proxy-auto enabled"

apt-proxy-auto-disable:
	@echo "🛑 [make] Disabling apt-proxy-auto timer and removing proxy file"
	@$(run_as_root) systemctl disable --now apt-proxy-auto.timer || true
	@$(run_as_root) rm -f /etc/apt/apt.conf.d/01proxy
	@echo "✅ [make] apt-proxy-auto disabled"

apt-proxy-auto-status:
	@echo "🔎 [make] apt-proxy-auto status"
	@$(run_as_root) systemctl status --no-pager apt-proxy-auto.timer || true
	@echo "📄 [make] Current APT proxy config (/etc/apt/apt.conf.d/01proxy):"
	@$(run_as_root) sh -c 'test -f /etc/apt/apt.conf.d/01proxy && cat /etc/apt/apt.conf.d/01proxy || echo "(absent → direct mirrors)"'
