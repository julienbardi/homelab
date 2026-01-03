# ============================================================
# mk/50_dnsmasq.mk — dnsmasq orchestration
# ============================================================

# ------------------------------------------------------------
# DNS policy & split-horizon invariants
# ------------------------------------------------------------
# Contract:
# - INTERNAL_HOSTS defines all hostnames treated as internal by Caddy
# - Every INTERNAL_HOST must resolve via Unbound to a private IP
# - Public DNS must never expose private IPs
# - dns-preflight enforces these invariants

INTERNAL_HOSTS := \
	router.bardi.ch \
	dns.bardi.ch \
	vpn.bardi.ch \
	derp.bardi.ch \
	qnap.bardi.ch \
	nas.bardi.ch \
	dev.bardi.ch \
	apt.bardi.ch

DNSMASQ_CONF_SRC_DIR := $(HOMELAB_DIR)/config/dnsmasq
DNSMASQ_CONF_FILES := $(wildcard $(DNSMASQ_CONF_SRC_DIR)/*.conf)

DNSMASQ_CONF_DIR := /usr/ugreen/etc/dnsmasq/dnsmasq.d

.PHONY: check-public-dns check-internal-dns dns-preflight

check-public-dns:
	@echo "[check] Verifying public DNS CNAMEs"
	@cname=$$(dig +short apt.bardi.ch CNAME | sed 's/\.$$//'); \
	if [ "$$cname" != "bardi.ch" ]; then \
		echo "❌ apt.bardi.ch must be a CNAME to bardi.ch"; \
		exit 1; \
	fi

check-internal-dns:
	@echo "[check] Verifying internal DNS coverage"
	@for host in $(INTERNAL_HOSTS); do \
		count=$$(dig @10.89.12.4 +short $$host A | wc -l); \
		if [ "$$count" -ne 1 ]; then \
			echo "❌ $$host must resolve to exactly one internal A record"; \
			echo "👉 Add or fix it in config/unbound/local-internal.conf"; \
			exit 1; \
		fi; \
	done

dns-preflight: check-public-dns check-internal-dns check-caddy-internal-hosts
	@echo "✅ DNS preflight checks passed"

CADDY_INTERNAL_HOSTS_FILE := $(HOMELAB_DIR)/config/caddy/internal-hosts.txt

.PHONY: check-caddy-internal-hosts

check-caddy-internal-hosts:
	@echo "[check] Verifying Caddy internal host restrictions"
	@test -f $(CADDY_INTERNAL_HOSTS_FILE) || \
		( echo "❌ Missing $(CADDY_INTERNAL_HOSTS_FILE)"; exit 1 )
	@for host in $(INTERNAL_HOSTS); do \
		if ! grep -qx "$$host" $(CADDY_INTERNAL_HOSTS_FILE); then \
			echo "❌ $$host is internal but not restricted in Caddy"; \
			echo "👉 Add it to config/caddy/internal-hosts.txt"; \
			exit 1; \
		fi; \
	done
	@echo "✅ All internal hosts are explicitly restricted in Caddy"

.PHONY: install-dnsmasq deploy-dnsmasq-config \
		check-dnsmasq-udp-buffers restore-dnsmasq-udp-buffers

install-dnsmasq:
	@$(call apt_install,dnsmasq,dnsmasq)

deploy-dnsmasq-config: install-dnsmasq check-dnsmasq-udp-buffers
	@echo "📄 [make] Deploying dnsmasq fragments"
	@test -d $(DNSMASQ_CONF_SRC_DIR) || { echo "❌ Missing $(DNSMASQ_CONF_SRC_DIR)"; exit 1; }

	@$(run_as_root) install -d -m 0755 $(DNSMASQ_CONF_DIR)

	@for f in $(DNSMASQ_CONF_FILES); do \
		echo "  → $$(basename $$f)"; \
		$(run_as_root) install -m 0644 -o root -g root $$f $(DNSMASQ_CONF_DIR)/$$(basename $$f); \
	done

	@echo "[make] Restarting dnsmasq service"
	@$(run_as_root) systemctl restart dnsmasq
	@$(run_as_root) systemctl is-active --quiet dnsmasq || \
		( echo "❌ dnsmasq failed to start"; \
			$(run_as_root) systemctl status --no-pager dnsmasq; \
			exit 1 )

	@echo "✅ dnsmasq running"
	@echo "✅ dnsmasq fragments deployed"

check-dnsmasq-udp-buffers:
	@echo "🔍 [make] Checking kernel UDP receive buffers for dnsmasq"
	@$(run_as_root) sh -eu -c '\
		REQUIRED_RMEM_MAX=8388608; \
		REQUIRED_RMEM_DEFAULT=8388608; \
		CUR_RMEM_MAX=$$(sysctl -n net.core.rmem_max); \
		CUR_RMEM_DEFAULT=$$(sysctl -n net.core.rmem_default); \
		if [ $$CUR_RMEM_MAX -lt $$REQUIRED_RMEM_MAX ] || \
		   [ $$CUR_RMEM_DEFAULT -lt $$REQUIRED_RMEM_DEFAULT ]; then \
			echo "🔧 [make] Updating UDP receive buffers"; \
			sysctl -w net.core.rmem_max=$$REQUIRED_RMEM_MAX >/dev/null; \
			sysctl -w net.core.rmem_default=$$REQUIRED_RMEM_DEFAULT >/dev/null; \
			echo "✅ [make] UDP receive buffers updated"; \
			echo "⚠️ NOTE: values updated for current boot only"; \
			echo "⚠️ To persist:"; \
			echo "    sudo tee /etc/sysctl.d/99-dns-warm.conf <<EOF"; \
			echo "# Required for dns-warm-async (lossless UDP fan-in)"; \
			echo "net.core.rmem_max = 8388608"; \
			echo "net.core.rmem_default = 8388608"; \
			echo "# UGOS defaults:"; \
			echo "# net.core.rmem_max = 8388608"; \
			echo "# net.core.rmem_default = 212992"; \
			echo "EOF"; \
			echo "    # then reboot or run: sudo sysctl --system"; \
		else \
			echo "✅ [make] UDP receive buffers already OK"; \
		fi'
restore-dnsmasq-udp-buffers:
	@echo "↩️  [make] Restoring UGOS UDP buffer defaults"
	@$(run_as_root) sh -eu -c '\
		sysctl -w net.core.rmem_max=8388608 >/dev/null; \
		sysctl -w net.core.rmem_default=212992 >/dev/null; \
		echo "✅ [make] UGOS defaults restored"'
