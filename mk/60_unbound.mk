# mk/60_unbound.mk — Unbound orchestration (IGOS-safe, config-only, pure DAG)

UNBOUND_RESTART_STAMP := $(STAMP_DIR)/unbound.restart
STAMP_UNBOUND_ANCHOR  := $(STAMP_DIR)/unbound_anchor.sha256

SYSCTL_UNBOUND_SRC := $(REPO_ROOT)/config/sysctl/99-unbound-buffers.conf
SYSCTL_UNBOUND_DST := /etc/sysctl.d/99-unbound-buffers.conf

UNBOUND_CONF_SRC := $(REPO_ROOT)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_LOCAL_INTERNAL_SRC := $(REPO_ROOT)/config/unbound/unbound.conf.d/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

.PHONY: \
	deploy-unbound \
	deploy-unbound-sysctl \
	update-root-hints \
	ensure-dnssec-trust-anchor \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	unbound-health

# ------------------------------------------------------------
# Sysctl (safe: kernel tuning only)
# ------------------------------------------------------------
deploy-unbound-sysctl: ensure-run-as-root
	@changed=0; rc=0; \
	$(call install_file,$(SYSCTL_UNBOUND_SRC),$(SYSCTL_UNBOUND_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 sysctl config updated — reloading"; \
		$(run_as_root) sysctl --system >/dev/null; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# ------------------------------------------------------------
# Root hints (pure data)
# ------------------------------------------------------------
update-root-hints: ensure-run-as-root
	@echo "🌐 Installing static root hints"
	@$(run_as_root) install -d -m 0750 -o root -g unbound /var/lib/unbound
	@$(run_as_root) install -m 0644 -o root -g unbound $(REPO_ROOT)/config/unbound/root.hints /var/lib/unbound/root.hints
	@echo "✅ root hints installed"

# ------------------------------------------------------------
# Trust anchor (stamp-driven, no service control)
# ------------------------------------------------------------
ensure-dnssec-trust-anchor: ensure-run-as-root $(STAMP_UNBOUND_ANCHOR)
	@echo "✅ root key present"

$(STAMP_UNBOUND_ANCHOR):
	@echo "🔑 Ensuring DNSSEC trust anchor -> /var/lib/unbound/root.key"
	@$(run_as_root) sh -c '\
		set -euo pipefail; \
		install -d -m 0750 -o root -g unbound /var/lib/unbound; \
		unbound-anchor -a /var/lib/unbound/root.key; \
		chown unbound:unbound /var/lib/unbound/root.key; \
		chmod 0644 /var/lib/unbound/root.key; \
		sha256sum /var/lib/unbound/root.key | awk "{print \$$1}" > "$(STAMP_UNBOUND_ANCHOR)"; \
		echo "🔐 DNSSEC trust anchor updated"; \
	'

# ------------------------------------------------------------
# Config deployment (pure, IGOS-safe)
# ------------------------------------------------------------
deploy-unbound-config: ensure-run-as-root
	@$(run_as_root) install -d -m 0755 /etc/unbound /etc/unbound/unbound.conf.d
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_CONF_SRC),$(UNBOUND_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound.conf updated — restarting homelab-unbound.service"; \
		$(run_as_root) systemctl restart homelab-unbound.service; \
	fi


deploy-unbound-local-internal: ensure-run-as-root
	@$(run_as_root) install -m 0644 -o root -g root $(UNBOUND_LOCAL_INTERNAL_SRC) $(UNBOUND_LOCAL_INTERNAL_DST)

# ------------------------------------------------------------
# Unbound health (IGOS-safe, read-only, no lifecycle control)
# ------------------------------------------------------------
unbound-health: ensure-run-as-root
	@echo "🔍 Unbound health check (IGOS-safe)"

	# 1. Process check
	@if pgrep -x unbound >/dev/null 2>&1; then \
		echo "   • ✅ process: unbound running"; \
	else \
		echo "   • ❌ process: unbound NOT running"; \
		exit 1; \
	fi

	# 2. Control socket check (IGOS uses /var/lib/unbound)
	@if [ -S /var/lib/unbound/unbound.ctl ]; then \
		echo "   • ✅ control socket: present"; \
	else \
		echo "   • ❌ control socket: missing (/var/lib/unbound/unbound.ctl)"; \
		exit 1; \
	fi

	# 3. PID file check
	@if [ -f /var/lib/unbound/unbound.pid ]; then \
		echo "   • ✅ pid file: present"; \
	else \
		echo "   • ❌ pid file: missing (/var/lib/unbound/unbound.pid)"; \
		exit 1; \
	fi

	# 4. DNS functional check (internal)
	@if [ "$$(dig +short @127.0.0.1 apt.bardi.ch CNAME)" = "nas.bardi.ch." ]; then \
		echo "   • ✅ DNS resolution: internal domain OK"; \
	else \
		echo "   • ❌ DNS resolution: internal domain FAILED"; \
		exit 1; \
	fi

	# 5. DNS functional check (external)
	@if dig +short @127.0.0.1 cloudflare.com A >/dev/null 2>&1; then \
		echo "   • ✅ DNS resolution: external domain OK"; \
	else \
		echo "   • ❌ DNS resolution: external domain FAILED"; \
		exit 1; \
	fi

	@echo "🎉 Unbound health: ALL CHECKS PASSED"

.PHONY: enable-homelab-unbound

enable-homelab-unbound: ensure-run-as-root
	@echo "🚀 Enabling homelab-unbound.service"
	@$(run_as_root) systemctl daemon-reload
	@$(run_as_root) systemctl enable --now homelab-unbound.service
	@echo "🟢 homelab-unbound enabled and started"

deploy-homelab-unbound-service:
	@$(run_as_root) install -o root -g root -m 0644 $(REPO_ROOT)/config/systemd/homelab-unbound.service /etc/systemd/system/homelab-unbound.service
	@$(run_as_root) systemctl daemon-reload

deploy-unbound: deploy-unbound-config deploy-unbound-local-internal deploy-homelab-unbound-service

.PHONY: enable-unbound
enable-unbound: enable-homelab-unbound

.PHONY: verify-internal-dns
verify-internal-dns: ensure-run-as-root
	@echo "🔍 Verifying internal DNS"
	@if [ "$$(dig +short @127.0.0.1 -p 15335 apt.bardi.ch CNAME)" = "nas.bardi.ch." ]; then \
		echo "   • ✅ internal DNS OK"; \
	else \
		echo "   • ❌ internal DNS FAILED"; \
		exit 1; \
	fi
