# ============================================================
# mk/60_unbound.mk — Unbound orchestration
# ============================================================

# --- Deployment ---
.PHONY: install-unbound install-dnsutils \
		deploy-unbound-config deploy-unbound-service deploy-unbound \
		update-root-hints update-root-key

install-unbound:
	@$(call apt_install,unbound,unbound)

install-dnsutils:
	@$(call apt_install,dig,dnsutils)

UNBOUND_CONF_SRC := $(HOMELAB_DIR)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

# --- Root hints ---
update-root-hints:
	@echo "🌐 [make] Updating root hints → /var/lib/unbound/root.hints"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@$(run_as_root) curl -s -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
	@$(run_as_root) chown root:unbound /var/lib/unbound/root.hints
	@$(run_as_root) chmod 0644 /var/lib/unbound/root.hints
	@echo "✅ [make] root hints updated"

# --- Trust anchor ---
ensure-root-key:
	@echo "🔑 [make] Ensuring DNSSEC trust anchor → /var/lib/unbound/root.key"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@if [ ! -f /var/lib/unbound/root.key ]; then \
		$(run_as_root) unbound-anchor -a /var/lib/unbound/root.key || true; \
		$(run_as_root) chown root:unbound /var/lib/unbound/root.key || true; \
		$(run_as_root) chmod 0644 /var/lib/unbound/root.key || true; \
	fi
	@echo "✅ [make] root key present"

deploy-unbound-config: update-root-hints ensure-root-key
	@echo "📄 [make] Deploying unbound.conf → /etc/unbound"
	@$(run_as_root) install -d -m 0755 /etc/unbound
	@$(run_as_root) install -m 0644 $(UNBOUND_CONF_SRC) $(UNBOUND_CONF_DST)
	@$(run_as_root) chown root:root $(UNBOUND_CONF_DST)
	@$(run_as_root) mkdir -p /run/unbound/unbound
	@$(run_as_root) chown unbound:unbound /run/unbound/unbound
	@$(run_as_root) unbound-checkconf $(UNBOUND_CONF_DST) || { echo "❌ invalid config"; exit 1; }
	@echo "✅ [make] unbound.conf deployed"

UNBOUND_SERVICE_SRC := $(HOMELAB_DIR)/config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

deploy-unbound-service:
	@echo "⚙️ [make] Deploying unbound.service → /etc/systemd/system"
	@$(run_as_root) install -m 0644 $(UNBOUND_SERVICE_SRC) $(UNBOUND_SERVICE_DST)
	@$(run_as_root) chown root:root $(UNBOUND_SERVICE_DST)
	@$(run_as_root) systemctl daemon-reload
	@echo "✅ [make] unbound.service deployed"

deploy-unbound: deploy-unbound-config deploy-unbound-service
	@echo "🔄 [make] Restarting unbound service"
	@$(run_as_root) systemctl enable --now unbound || { echo "❌ failed to enable"; exit 1; }
	@$(run_as_root) systemctl restart unbound || { echo "❌ failed to restart"; exit 1; }
	@$(run_as_root) systemctl status --no-pager unbound

# --- Remote control ---
.PHONY: setup-unbound-control
setup-unbound-control:
	@echo "🔑 [make] Setting up Unbound remote-control"
	@if [ ! -f /etc/unbound/unbound_server.key ]; then \
		echo "📦 [make] Generating control certificates..."; \
		$(run_as_root) unbound-control-setup; \
	fi
	# Fix ownership: both server and control certs root:unbound
	@$(run_as_root) chown root:unbound /etc/unbound/unbound_server.{key,pem}
	@$(run_as_root) chmod 0640 /etc/unbound/unbound_server.{key,pem}
	@$(run_as_root) chown root:unbound /etc/unbound/unbound_control.{key,pem}
	@$(run_as_root) chmod 0640 /etc/unbound/unbound_control.{key,pem}
	@echo "📝 [make] Writing client config → /etc/unbound/unbound-control.conf"
	@$(run_as_root) sh -c 'printf "%s\n" \
		"control-interface: /run/unbound.ctl" \
		"server-key-file: /etc/unbound/unbound_server.key" \
		"server-cert-file: /etc/unbound/unbound_server.pem" \
		"control-key-file: /etc/unbound/unbound_control.key" \
		"control-cert-file: /etc/unbound/unbound_control.pem" \
		> /etc/unbound/unbound-control.conf'
	@$(run_as_root) chown root:root /etc/unbound/unbound-control.conf
	@$(run_as_root) chmod 0644 /etc/unbound/unbound-control.conf
	@$(run_as_root) systemctl restart unbound || { echo "❌ restart failed"; exit 1; }
	@echo "✅ [make] remote-control initialized"
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
		$(run_as_root) /usr/sbin/unbound-control -c /etc/unbound/unbound.conf -s /run/unbound.ctl status || { echo "❌ unbound-control (socket) not responding"; exit 1; }; \
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
	@$(run_as_root) chown root:unbound /etc/unbound/unbound_{server,control}.{key,pem}
	@$(run_as_root) chmod 0640 /etc/unbound/unbound_{server,control}.{key,pem}

# --- Runtime / Benchmark ---
.PHONY: dns rotate dns-bench dns-all dns-reset dns-health dns-watch

dns: install-unbound install-dnsutils
	@echo "🔍 [make] Running dns_setup.sh"
	@$(run_as_root) bash $(HOMELAB_DIR)/scripts/setup/dns_setup.sh

rotate:
	@echo "🔄 [make] Refreshing DNSSEC trust anchors"
	@$(run_as_root) bash scripts/helpers/rotate-unbound-rootkeys.sh

dns-bench: install-dnsutils
	@echo "🌐 [make] Downloading OpenDNS top domains list..."
	@curl -s -o /tmp/opendns-top-domains.txt https://raw.githubusercontent.com/opendns/public-domain-lists/master/opendns-top-domains.txt
	@echo "⚡ [make] Priming Unbound cache..."
	@while read -r domain; do \
		dig @"10.89.12.4" $$domain A +short >/dev/null; \
	done < /tmp/opendns-top-domains.txt
	@echo "🔥 [make] Running dnsperf load test (30s @ 1000 qps)..."
	@dnsperf -s 10.89.12.4 -d /tmp/opendns-top-domains.txt -l 30 -q 1000
	@echo "✅ [make] DNS benchmark complete"

.PHONY: install-unbound-tmpfiles

install-unbound-tmpfiles:
	@echo "🔧 [make] Ensuring unbound tmpfiles entry is installed"
	@test -x scripts/setup/setup-unbound-tmpfiles.sh || chmod +x scripts/setup/setup-unbound-tmpfiles.sh
	@$(run_as_root) ./scripts/setup/setup-unbound-tmpfiles.sh

# --- Full bootstrap: ensure systemd helper, then deploy and run DNS  ---
dns-all: install-unbound-tmpfiles enable-systemd deploy-unbound setup-unbound-control dns
	@echo "🚀 [make] Full Unbound bootstrap complete (deploy → control → runtime)"

# --- Reset + bootstrap ---
dns-reset:
	@echo "🧹 [make] Stopping Unbound and clearing state..."
	@$(run_as_root) systemctl stop unbound || true
	@$(run_as_root) rm -rf /run/unbound /var/lib/unbound/* || true
	@echo "🔄 [make] Redeploying Unbound configs and service..."
	@$(MAKE) deploy-unbound
	@echo "🔑 [make] Re-initializing remote-control..."
	@$(MAKE) setup-unbound-control
	@echo "🔍 [make] Running dns_setup.sh..."
	@$(MAKE) dns
	@echo "✅ [make] DNS reset + bootstrap complete"

# --- Health check ---
dns-health:
	@echo "🩺 [make] Checking Unbound health and cache stats..."
	@$(run_as_root) -u unbound sh -c 'unbound-control stats_noreset' | awk '\
		/^num.queries/       {print "📊 Total queries: " $$2} \
		/^num.cachehits/     {print "⚡ Cache hits: " $$2} \
		/^num.cachemiss/     {print "🐢 Cache misses: " $$2} \
		/^avg.response.time/ {print "⏱️ Avg response time: " $$2 " ms"} \
	'
	@echo "✅ [make] dns-health check complete"

# --- Live log watch ---
dns-watch:
	@echo "👀 [make] Tailing Unbound logs (Ctrl+C to exit)..."
	@$(run_as_root) journalctl -u unbound -f -n 50 | sed -u \
		-e 's/warning:/⚠️ warning:/g' \
		-e 's/error:/❌ error:/g' \
		-e 's/notice:/ℹ️ notice:/g'
