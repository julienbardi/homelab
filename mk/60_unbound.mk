# ============================================================
# mk/60_unbound.mk — Unbound orchestration
# ============================================================

.PHONY: enable-unbound install-pkg-unbound remove-pkg-unbound
enable-unbound: \
	install-pkg-unbound \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-service \
	deploy-unbound-control-config
	@echo "🔄 unbound restart requested (homelab configuration)"
	@$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || true
	@$(run_as_root) systemctl restart unbound
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ Unbound failed to start"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✅ Unbound enabled and running"

# ------------------------------------------------------------
# Unbound
# ------------------------------------------------------------
install-pkg-unbound:
	@if command -v unbound >/dev/null; then \
		echo "🔁 unbound already installed"; \
	else \
		echo "📦 Installing unbound"; \
		$(call apt_install,unbound,unbound); \
	fi
	@$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || true
	@echo "✅ Unbound installed and enabled"

remove-pkg-unbound:
	$(call apt_remove,unbound)

# --- Deployment ---
.PHONY: \
	deploy-unbound-config \
	deploy-unbound-service \
	deploy-unbound \
	deploy-unbound-control-config \
	update-root-hints ensure-root-key

UNBOUND_CONF_SRC := $(HOMELAB_DIR)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_CONTROL_CONF_SRC := $(HOMELAB_DIR)/config/unbound/unbound-control.conf
UNBOUND_CONTROL_CONF_DST := /etc/unbound/unbound-control.conf

.PHONY: assert-unbound-tools
assert-unbound-tools:
	@command -v unbound >/dev/null || \
		( echo "❌ unbound not installed. Run: make prereqs"; exit 1 )
	@command -v dig >/dev/null || \
		( echo "❌ dig not installed. Run: make prereqs"; exit 1 )
	@command -v unbound-control >/dev/null || \
		( echo "❌ unbound-control not installed. Run: make prereqs"; exit 1 )

# --- Root hints ---
update-root-hints:
	@echo "🌐 [make] Updating root hints → /var/lib/unbound/root.hints"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@curl -s https://www.internic.net/domain/named.root \
		| $(run_as_root) install -m 0644 -o root -g unbound /dev/stdin /var/lib/unbound/root.hints
	@echo "✅ [make] root hints updated"

# --- Trust anchor ---
ensure-root-key:
	@echo "🔑 [make] Ensuring DNSSEC trust anchor → /var/lib/unbound/root.key"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@if [ ! -f /var/lib/unbound/root.key ]; then \
		$(run_as_root) unbound-anchor -a /tmp/root.key; \
		$(run_as_root) install -m 0644 -o root -g unbound /tmp/root.key /var/lib/unbound/root.key; \
	fi
	@echo "✅ [make] root key present"

deploy-unbound-config: update-root-hints ensure-root-key
	@echo "📄 [make] Deploying unbound.conf → /etc/unbound"
	@$(run_as_root) install -d -m 0755 /etc/unbound
	@$(run_as_root) install -m 0644 -o root -g root $(UNBOUND_CONF_SRC) $(UNBOUND_CONF_DST)
	@$(run_as_root) unbound-checkconf $(UNBOUND_CONF_DST) || { echo "❌ invalid config"; exit 1; }
	@echo "✅ [make] unbound.conf deployed"

deploy-unbound-control-config:
	@echo "📄 [make] Deploying unbound-control.conf → /etc/unbound"
	@$(run_as_root) install -m 0644 -o root -g root \
		$(UNBOUND_CONTROL_CONF_SRC) $(UNBOUND_CONTROL_CONF_DST)

UNBOUND_SERVICE_SRC := $(HOMELAB_DIR)/config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

deploy-unbound-service:
	@echo "⚙️ [make] Deploying unbound.service → /etc/systemd/system"
	@$(run_as_root) install -m 0644 -o root -g root $(UNBOUND_SERVICE_SRC) $(UNBOUND_SERVICE_DST)
	@$(run_as_root) systemctl daemon-reload
	@echo "✅ [make] unbound.service deployed"

UNBOUND_LOCAL_INTERNAL_SRC := $(HOMELAB_DIR)/config/unbound/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

.PHONY: deploy-unbound-local-internal
deploy-unbound-local-internal:
	@echo "📄 [make] Deploying internal DNS overrides → unbound"
	@$(run_as_root) install -m 0644 -o root -g root \
		$(UNBOUND_LOCAL_INTERNAL_SRC) \
		$(UNBOUND_LOCAL_INTERNAL_DST)
	@$(run_as_root) unbound-checkconf || \
		( echo "❌ invalid unbound configuration after installing internal overrides"; exit 1 )
	@$(run_as_root) systemctl reload unbound
	@echo "✅ [make] Internal DNS overrides active"

# --- Systemd drop-in for fixing /run/unbound.ctl ownership ---
UNBOUND_DROPIN_SRC := $(HOMELAB_DIR)/config/systemd/unbound.service.d/99-fix-unbound-ctl.conf
UNBOUND_DROPIN_DST := /etc/systemd/system/unbound.service.d/99-fix-unbound-ctl.conf

.PHONY: install-unbound-systemd-dropin
install-unbound-systemd-dropin:
	@echo "🔧 [make] Installing unbound systemd drop-in"
	@$(run_as_root) install -d /etc/systemd/system/unbound.service.d
	@$(run_as_root) install -m 0644 -o root -g root $(UNBOUND_DROPIN_SRC) $(UNBOUND_DROPIN_DST)
	@$(run_as_root) systemctl daemon-reload
	@echo "[make] Restarting unbound service (drop-in)"
	@$(run_as_root) systemctl restart unbound
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ unbound failed to start after drop-in install"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✅ unbound running (drop-in applied)"
	@echo "✅ [make] unbound systemd drop-in installed"

deploy-unbound: dns-preflight \
				install-pkg-unbound \
				deploy-unbound-config \
				deploy-unbound-local-internal \
				deploy-unbound-service \
				deploy-unbound-control-config
	@echo "🔄 [make] Restarting unbound service"
	@$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || { echo "❌ failed to enable unbound";  exit 1; }
	@$(run_as_root) systemctl restart unbound
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ unbound failed to start"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✅ unbound running"

# --- Remote control ---
.PHONY: setup-unbound-control
setup-unbound-control:
	@echo "🔑 [make] Setting up Unbound remote-control"
	@if [ ! -f /etc/unbound/unbound_server.key ]; then \
		echo "📦 [make] Generating control certificates..."; \
		$(run_as_root) unbound-control-setup; \
	fi
	# Fix ownership: both server and control certs root:unbound
	@$(run_as_root) install -m 0640 -o root -g unbound /etc/unbound/unbound_{server,control}.{key,pem} /etc/unbound/
	@echo "📝 [make] Writing client config → /etc/unbound/unbound-control.conf"
	@$(run_as_root) sh -c 'printf "%s\n" \
		"remote-control:" \
		"    control-interface: /run/unbound.ctl" \
		"    server-key-file: /etc/unbound/unbound_server.key" \
		"    server-cert-file: /etc/unbound/unbound_server.pem" \
		"    control-key-file: /etc/unbound/unbound_control.key" \
		"    control-cert-file: /etc/unbound/unbound_control.pem" \
		> /etc/unbound/unbound-control.conf'
	@echo "[make] Restarting unbound service (remote-control)"
	@$(run_as_root) systemctl restart unbound || { echo "❌ restart failed"; exit 1; }
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ unbound failed to start after remote-control setup"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✅ unbound running (remote-control enabled)"
	@echo "🔎 [make] Testing connectivity..."
	@sleep 2
	@if [ -e /run/unbound.ctl ] && ! ss -lxpn | grep -q '/run/unbound.ctl'; then \
		echo "Removing stale /run/unbound.ctl and restarting unbound"; \
		$(run_as_root) rm -f /run/unbound.ctl; \
		$(run_as_root) systemctl restart unbound; \
		sleep 1; \
	fi
	@if [ -e /run/unbound.ctl ]; then \
		echo "→ using unix socket /run/unbound.ctl"; \
		$(run_as_root) /usr/sbin/unbound-control -c /etc/unbound/unbound-control.conf -s /run/unbound.ctl status || { echo "❌ unbound-control (socket) not responding"; exit 1; }; \
	else \
		echo "❌ unix socket /run/unbound.ctl not present; please ensure Unbound is configured to use the socket and restart"; \
		journalctl -u unbound -n 200 --no-pager | grep -i -E 'control|socket|error|refused' -n -C2 | sed -n '1,200p'; \
		exit 1; \
	fi
	@echo "✅ [make] unbound-control is responding"

.PHONY: reset-unbound-control
reset-unbound-control:
	@echo "♻️ Forcing regeneration of Unbound control certificates"
	@$(run_as_root) rm -f /etc/unbound/unbound_{server,control}.{key,pem}
	@$(run_as_root) unbound-control-setup
	@$(run_as_root) install -m 0640 -o root -g unbound /etc/unbound/unbound_{server,control}.{key,pem} /etc/unbound/

.PHONY: dns-runtime-check
dns-runtime-check: assert-unbound-running
	@dig @127.0.0.1 -p 5335 . NS +short >/dev/null || \
		( echo "❌ Unbound not resolving root NS"; exit 1 )

# --- Runtime / Benchmark ---
.PHONY: dns rotate dns-bench dns-all dns-reset dns-health dns-watch dns-runtime

dns:
	@echo "🔍 [make] Running dns_setup.sh"
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/setup/dns_setup.sh

rotate:
	@echo "🔄 [make] Refreshing DNSSEC trust anchors"
	@$(run_as_root) bash scripts/helpers/rotate-unbound-rootkeys.sh

dns-bench:
	@echo "🌐 [make] Downloading OpenDNS top domains list..."
	@curl -s -o /tmp/opendns-top-domains.txt https://raw.githubusercontent.com/opendns/public-domain-lists/master/opendns-top-domains.txt
	@echo "⚡ [make] Priming Unbound cache..."
	@while read -r domain; do \
		dig @"10.89.12.4" $$domain A +short >/dev/null; \
	done < /tmp/opendns-top-domains.txt
	@echo "🔥 [make] Running dnsperf load test (30s @ 1000 qps)..."
	@dnsperf -s 10.89.12.4 -d /tmp/opendns-top-domains.txt -l 30 -q 1000
	@echo "✅ [make] DNS benchmark complete"

dns-runtime: \
	enable-systemd \
	install-unbound-systemd-dropin \
	dnsdist \
	dns-warm-install \
	dns-warm-enable
	@echo "⚙️ [make] DNS runtime helpers ensured (dnsdist + dns-warm)"

# --- Reset + bootstrap ---
.PHONY: dns-reset-clean
dns-reset-clean:
	@echo "🧹 [make] Stopping Unbound and clearing state..."
	@$(run_as_root) systemctl stop unbound || true
	@$(run_as_root) rm -rf /run/unbound /var/lib/unbound/* || true

.PHONY: dns-reset
dns-reset: FORCE := $(FORCE)
dns-reset: CONF_FORCE := $(CONF_FORCE)
dns-reset: \
	assert-unbound-tools \
	dns-reset-clean \
	deploy-unbound \
	setup-unbound-control \
	dns
	@echo "✅ [make] DNS reset + bootstrap complete"

# --- Health check ---
dns-health: assert-unbound-tools assert-unbound-control
	@echo "🩺 [make] Checking Unbound health and cache stats..."
	sudo -u unbound unbound-control \
		-c /etc/unbound/unbound-control.conf \
		stats_noreset 2>/dev/null | awk '\
			/^num.queries/       {print "📊 Total queries: " $$2} \
			/^num.cachehits/     {print "⚡ Cache hits: " $$2} \
			/^num.cachemiss/     {print "🐢 Cache misses: " $$2} \
			/^avg.response.time/ {print "⏱️ Avg response time: " $$2 " ms"} \
		'
	@echo "✅ [make] dns-health check complete"

.PHONY: assert-unbound-control
assert-unbound-control:
	@test -f /etc/unbound/unbound-control.conf || \
		( echo "❌ unbound-control not configured. Run: make setup-unbound-control"; exit 1 )
	@sudo -u unbound unbound-control \
		-c /etc/unbound/unbound-control.conf \
		status >/dev/null 2>/dev/null || \
		( echo "❌ unbound-control not responding"; exit 1 )


# --- Live log watch ---
dns-watch:
	@echo "👀 [make] Tailing Unbound logs (Ctrl+C to exit)..."
	@$(run_as_root) journalctl -u unbound -f -n 50 | sed -u \
		-e 's/warning:/⚠️ warning:/g' \
		-e 's/error:/❌ error:/g' \
		-e 's/notice:/ℹ️ notice:/g'

sysctl:
	@echo "📄 Ensuring /etc/sysctl.d/99-unbound-buffers.conf exists and is correct..."
	@if ! [ -f /etc/sysctl.d/99-unbound-buffers.conf ] || \
	   ! grep -q "net.core.rmem_max = 8388608" /etc/sysctl.d/99-unbound-buffers.conf || \
	   ! grep -q "net.core.wmem_max = 8388608" /etc/sysctl.d/99-unbound-buffers.conf; then \
		echo "# Increase socket buffer sizes for Unbound DNS resolver" | $(run_as_root) tee /etc/sysctl.d/99-unbound-buffers.conf >/dev/null; \
		echo "net.core.rmem_max = 8388608" | $(run_as_root) tee -a /etc/sysctl.d/99-unbound-buffers.conf >/dev/null; \
		echo "net.core.wmem_max = 8388608" | $(run_as_root) tee -a /etc/sysctl.d/99-unbound-buffers.conf >/dev/null; \
		echo "✅ Wrote /etc/sysctl.d/99-unbound-buffers.conf"; \
	else \
		echo "🔁 /etc/sysctl.d/99-unbound-buffers.conf already correct"; \
	fi
	@echo "🔧 Reloading sysctl configuration..."
	@$(run_as_root) /sbin/sysctl --system >/dev/null
	@echo "🔄 Restarting Unbound to apply new buffer sizes..."
	@$(run_as_root) systemctl restart unbound
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ unbound failed to start after sysctl reload"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✔ Sysctl reload complete. Current buffer limits:"
	@/sbin/sysctl -q net.core.rmem_max net.core.wmem_max
