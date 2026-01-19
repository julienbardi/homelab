# ============================================================
# mk/60_unbound.mk — Unbound orchestration
# ============================================================

UNBOUND_RESTART_STAMP := $(STAMP_DIR)/unbound.restart

.PHONY: \
	enable-unbound \
	install-pkg-unbound \
	remove-pkg-unbound \
	deploy-unbound \
	deploy-unbound-config \
	deploy-unbound-service \
	deploy-unbound-control-config \
	deploy-unbound-local-internal \
	install-unbound-systemd-dropin \
	update-root-hints \
	ensure-root-key \
	assert-unbound-tools \
	assert-unbound-control \
	setup-unbound-control \
	reset-unbound-control \
	unbound-status \
	dns \
	dns-runtime \
	dns-runtime-check \
	dns-health \
	dns-watch \
	dns-reset \
	dns-reset-clean \
	dns-bench \
	rotate

enable-unbound: \
	install-pkg-unbound \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-service \
	deploy-unbound-control-config
	@if [ -f "$(UNBOUND_RESTART_STAMP)" ]; then \
		echo "🔄 unbound configuration changed — restarting"; \
		$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || true; \
		$(run_as_root) systemctl restart unbound; \
		$(run_as_root) rm -f $(UNBOUND_RESTART_STAMP); \
	else \
		echo "ℹ️ Unbound configuration unchanged — no restart needed"; \
	fi
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ Unbound failed to start"; \
		  echo "ℹ️  Run: make unbound-status"; \
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
UNBOUND_CONF_SRC := $(HOMELAB_DIR)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_CONTROL_CONF_SRC := $(HOMELAB_DIR)/config/unbound/unbound-control.conf
UNBOUND_CONTROL_CONF_DST := /etc/unbound/unbound-control.conf

assert-unbound-tools:
	@PATH=/usr/sbin:/sbin:$$PATH command -v unbound >/dev/null || \
		( echo "❌ unbound not installed. Run: make prereqs"; exit 1 )
	@command -v dig >/dev/null || \
		( echo "❌ dig not installed. Run: make prereqs"; exit 1 )
	@PATH=/usr/sbin:/sbin:$$PATH command -v unbound-control >/dev/null || \
		( echo "❌ unbound-control not installed. Run: make prereqs"; exit 1 )

# --- Root hints ---
update-root-hints:
	@echo "🌐 Updating root hints → /var/lib/unbound/root.hints"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@tmp=$$(mktemp); \
	if curl -fsSL \
		--connect-timeout 10 \
		--max-time 20 \
		https://www.internic.net/domain/named.root \
		-o $$tmp; then \
		$(run_as_root) install -m 0644 -o root -g unbound $$tmp /var/lib/unbound/root.hints; \
		echo "✅ root hints updated"; \
	else \
		echo "⚠️ root hints download failed — keeping existing file"; \
	fi; \
	rm -f $$tmp

# --- Trust anchor ---
ensure-root-key:
	@echo "🔑 Ensuring DNSSEC trust anchor → /var/lib/unbound/root.key"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@if [ ! -f /var/lib/unbound/root.key ]; then \
		$(run_as_root) unbound-anchor -a /tmp/root.key; \
		$(run_as_root) install -m 0644 -o root -g unbound /tmp/root.key /var/lib/unbound/root.key; \
	fi
	@echo "✅ root key present"

deploy-unbound-config: update-root-hints ensure-root-key
	@$(run_as_root) install -d -m 0755 /etc/unbound
	@changed=0; \
	$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		$(UNBOUND_CONF_SRC) $(UNBOUND_CONF_DST) root root 0644; \
	rc=$$?; \
	if [ $$rc -eq 3 ]; then \
		changed=1; \
	elif [ $$rc -ne 0 ]; then \
		exit $$rc; \
	fi; \
	$(run_as_root) unbound-checkconf $(UNBOUND_CONF_DST) || { echo "❌ invalid config"; exit 1; }; \
	if [ $$changed -eq 1 ]; then \
		echo "→ unbound.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

deploy-unbound-control-config:
	@changed=0; \
	$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		$(UNBOUND_CONTROL_CONF_SRC) \
		$(UNBOUND_CONTROL_CONF_DST) \
		root root 0644; \
	rc=$$?; \
	if [ $$rc -eq 3 ]; then \
		changed=1; \
	elif [ $$rc -ne 0 ]; then \
		exit $$rc; \
	fi; \
	if [ $$changed -eq 1 ]; then \
		echo "→ unbound-control.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

UNBOUND_SERVICE_SRC := $(HOMELAB_DIR)/config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

deploy-unbound-service:
	@changed=0; \
	$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		$(UNBOUND_SERVICE_SRC) \
		$(UNBOUND_SERVICE_DST) \
		root root 0644; \
	rc=$$?; \
	if [ $$rc -eq 3 ]; then \
		changed=1; \
	elif [ $$rc -ne 0 ]; then \
		exit $$rc; \
	fi; \
	if [ $$changed -eq 1 ]; then \
		echo "→ unbound.service updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
		$(run_as_root) systemctl daemon-reload; \
	fi

UNBOUND_LOCAL_INTERNAL_SRC := $(HOMELAB_DIR)/config/unbound/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

deploy-unbound-local-internal:
	@changed=0; \
	$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		$(UNBOUND_LOCAL_INTERNAL_SRC) \
		$(UNBOUND_LOCAL_INTERNAL_DST) \
		root root 0644; \
	rc=$$?; \
	if [ $$rc -eq 3 ]; then \
		changed=1; \
	elif [ $$rc -ne 0 ]; then \
		exit $$rc; \
	fi; \
	$(run_as_root) unbound-checkconf || \
		( echo "❌ invalid unbound configuration after installing internal overrides"; exit 1 ); \
	if [ $$changed -eq 1 ]; then \
		echo "→ local-internal.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# --- Systemd drop-in for fixing /run/unbound.ctl ownership ---
UNBOUND_DROPIN_SRC := $(HOMELAB_DIR)/config/systemd/unbound.service.d/99-fix-unbound-ctl.conf
UNBOUND_DROPIN_DST := /etc/systemd/system/unbound.service.d/99-fix-unbound-ctl.conf

install-unbound-systemd-dropin:
	@$(run_as_root) install -d /etc/systemd/system/unbound.service.d
	@changed=0; \
	$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		$(UNBOUND_DROPIN_SRC) \
		$(UNBOUND_DROPIN_DST) \
		root root 0644; \
	rc=$$?; \
	if [ $$rc -eq 3 ]; then \
		changed=1; \
	elif [ $$rc -ne 0 ]; then \
		exit $$rc; \
	fi; \
	if [ $$changed -eq 1 ]; then \
		echo "→ unbound systemd drop-in updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
		$(run_as_root) systemctl daemon-reload; \
	fi

deploy-unbound:
	dns-preflight \
	install-pkg-unbound \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-service \
	deploy-unbound-control-config
	@echo "ℹ️ Unbound deployed (restart handled by enable-unbound)"

# --- Remote control ---
setup-unbound-control:
	@if [ ! -f /etc/unbound/unbound_server.key ]; then \
		echo "📦 Generating control certificates..."; \
		$(run_as_root) unbound-control-setup; \
	fi
	# Fix ownership: both server and control certs root:unbound
	@$(run_as_root) install -m 0640 -o root -g unbound /etc/unbound/unbound_{server,control}.{key,pem} /etc/unbound/
	@echo "📝 Writing client config → /etc/unbound/unbound-control.conf"
	@$(run_as_root) sh -c 'printf "%s\n" \
		"remote-control:" \
		"    control-interface: /run/unbound.ctl" \
		"    server-key-file: /etc/unbound/unbound_server.key" \
		"    server-cert-file: /etc/unbound/unbound_server.pem" \
		"    control-key-file: /etc/unbound/unbound_control.key" \
		"    control-cert-file: /etc/unbound/unbound_control.pem" \
		> /etc/unbound/unbound-control.conf'
	@echo "Restarting unbound service (remote-control)"
	@$(run_as_root) systemctl restart unbound || { echo "❌ restart failed"; exit 1; }
	@if [ -f "$(UNBOUND_RESTART_STAMP)" ]; then \
		echo "🔄 Restarted unbound — status:"; \
		$(run_as_root) systemctl status --no-pager unbound; \
	fi
	@$(run_as_root) systemctl is-active --quiet unbound || \
		( echo "❌ unbound failed to start after remote-control setup"; \
		  $(run_as_root) systemctl status --no-pager unbound; \
		  exit 1 )
	@echo "✅ unbound running (remote-control enabled)"
	@echo "🔎 Testing connectivity..."
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
	@echo "✅ unbound-control is responding"

reset-unbound-control:
	@echo "♻️ Forcing regeneration of Unbound control certificates"
	@$(run_as_root) rm -f /etc/unbound/unbound_{server,control}.{key,pem}
	@$(run_as_root) unbound-control-setup
	@$(run_as_root) install -m 0640 -o root -g unbound /etc/unbound/unbound_{server,control}.{key,pem} /etc/unbound/

dns-runtime-check: assert-unbound-running
	@dig @127.0.0.1 -p 5335 . NS +short >/dev/null || \
		( echo "❌ Unbound not resolving root NS"; exit 1 )

# --- Runtime / Benchmark ---
dns: enable-unbound dns-runtime dns-warm-install dns-health
	@echo "✅ DNS stack converged and healthy"

ROTATE_ROOTKEYS := /usr/local/bin/rotate-unbound-rootkeys.sh

rotate: $(ROTATE_ROOTKEYS)
	@echo "🔄 Refreshing DNSSEC trust anchors"
	@$(run_as_root) $(ROTATE_ROOTKEYS)

dns-bench:
	@echo "🌐 Downloading OpenDNS top domains list..."
	@curl -s -o /tmp/opendns-top-domains.txt https://raw.githubusercontent.com/opendns/public-domain-lists/master/opendns-top-domains.txt
	@echo "⚡ Priming Unbound cache..."
	@while read -r domain; do \
		dig @"10.89.12.4" $$domain A +short >/dev/null; \
	done < /tmp/opendns-top-domains.txt
	@echo "🔥 Running dnsperf load test (30s @ 1000 qps)..."
	@dnsperf -s 10.89.12.4 -d /tmp/opendns-top-domains.txt -l 30 -q 1000
	@echo "✅ DNS benchmark complete"

dns-runtime: \
	enable-systemd \
	install-unbound-systemd-dropin \
	dnsdist \
	dns-warm-install \
	dns-warm-enable
	@echo "⚙️ DNS runtime helpers ensured (dnsdist + dns-warm)"

# --- Reset + bootstrap ---
dns-reset-clean:
	@echo "🧹 Stopping Unbound and clearing state..."
	@$(run_as_root) systemctl stop unbound || true
	@$(run_as_root) rm -rf /run/unbound /var/lib/unbound/* || true

dns-reset: FORCE := $(FORCE)
dns-reset: CONF_FORCE := $(CONF_FORCE)
dns-reset: \
	assert-unbound-tools \
	dns-reset-clean \
	deploy-unbound \
	setup-unbound-control \
	dns
	@echo "✅ DNS reset + bootstrap complete"

# --- Health check ---
dns-health: assert-unbound-tools assert-unbound-control dns-runtime
	@echo "🩺 Checking Unbound health and cache stats..."
	@sudo -u unbound unbound-control \
	-c /etc/unbound/unbound-control.conf \
	stats_noreset 2>/dev/null | \
awk -F= '\
	/thread[0-9]+\.num\.queries=/        { q += $$2 } \
	/thread[0-9]+\.num\.cachehits=/      { h += $$2 } \
	/thread[0-9]+\.num\.cachemiss=/      { m += $$2 } \
	/thread[0-9]+\.recursion\.time\.avg=/ { t += $$2; n++ } \
	END { \
		if (!q) exit; \
		hp = (h/q)*100; \
		mp = (m/q)*100; \
		rt = (n ? (t/n)*1000 : 0); \
		printf "Metric                    Value        Ratio\n"; \
		printf "────────────────────────────────────────────\n"; \
		printf "%-22s %10d %9.1f%%\n", "Total queries", q, 100; \
		printf "%-22s %10d %9.1f%%\n", "Cache hits", h, hp; \
		printf "%-22s %10d %9.1f%%\n", "Cache misses", m, mp; \
		printf "%-22s %10.2f ms\n", "Avg recursion time", rt; \
		printf "\n"; \
		if (hp < 10) \
			printf "Verdict: ℹ️ Expected after restart; will normalize within minutes\n"; \
		else if (rt > 20) \
			printf "Verdict: ⚠️ high recursion latency\n"; \
		else \
			printf "Verdict: ✅ healthy resolver\n"; \
	}'

	@echo "✅ dns-health check complete"

assert-unbound-control:
	@test -f /etc/unbound/unbound-control.conf || \
		( echo "❌ unbound-control not configured. Run: make setup-unbound-control"; exit 1 )
	@sudo -u unbound unbound-control \
		-c /etc/unbound/unbound-control.conf \
		status >/dev/null 2>/dev/null || \
		( echo "❌ unbound-control not responding"; exit 1 )


# --- Live log watch ---
dns-watch:
	@echo "👀 Tailing Unbound logs (Ctrl+C to exit)..."
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
		  echo "ℹ️ Run: make unbound-status"; \
		  exit 1 )
	@echo "✅ Sysctl reload complete. Current buffer limits:"
	@/sbin/sysctl -q net.core.rmem_max net.core.wmem_max

unbound-status:
	@$(run_as_root) systemctl status unbound --no-pager --lines=0