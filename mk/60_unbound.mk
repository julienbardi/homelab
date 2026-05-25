# mk/60_unbound.mk — Unbound orchestration (no recursive make, pure DAG)

UNBOUND_RESTART_STAMP := $(STAMP_DIR)/unbound.restart
STAMP_UNBOUND_ANCHOR  := $(STAMP_DIR)/unbound_anchor.sha256

SYSCTL_UNBOUND_SRC := $(REPO_ROOT)/config/sysctl/99-unbound-buffers.conf
SYSCTL_UNBOUND_DST := /etc/sysctl.d/99-unbound-buffers.conf

UNBOUND_CONF_SRC := $(REPO_ROOT)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_LOCAL_INTERNAL_SRC := $(REPO_ROOT)/config/unbound/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

UNBOUND_CONTROL_CONF_SRC := $(REPO_ROOT)/config/unbound/unbound-control.conf
UNBOUND_CONTROL_CONF_DST := /etc/unbound/unbound-control.conf

UNBOUND_SERVICE_SRC := $(REPO_ROOT)/config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

UNBOUND_DROPIN_SRC := $(REPO_ROOT)/config/systemd/unbound.service.d/99-fix-unbound-ctl.conf
UNBOUND_DROPIN_DST := /etc/systemd/system/unbound.service.d/99-fix-unbound-ctl.conf

.PHONY: \
	enable-unbound \
	deploy-unbound \
	deploy-unbound-sysctl \
	update-root-hints \
	ensure-dnssec-trust-anchor \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-control-config \
	deploy-unbound-service \
	install-unbound-systemd-dropin \
	dns-reset-clean \
	dns-reset \
	setup-unbound-control \
	unbound-status

# ------------------------------------------------------------
# Sysctl
# ------------------------------------------------------------
deploy-unbound-sysctl: ensure-run-as-root
	@changed=0; \
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
# Root hints (pure)
# ------------------------------------------------------------
# Installs the static root.hints file tracked in the repository.
# This ensures a deterministic, offline-capable deployment.
update-root-hints: ensure-run-as-root
	@echo "🌐 Installing static root hints from repository"
	@$(run_as_root) install -d -m 0770 -o root -g unbound /var/lib/unbound
	@$(run_as_root) install -m 0644 -o root -g unbound $(REPO_ROOT)/config/unbound/root.hints /var/lib/unbound/root.hints
	@echo "✅ root hints installed"

# ------------------------------------------------------------
# Trust anchor (stamp-driven, fast-path, single run_as_root)
# ------------------------------------------------------------
ensure-dnssec-trust-anchor: ensure-run-as-root $(STAMP_UNBOUND_ANCHOR)
	@echo "✅ root key present"

$(STAMP_UNBOUND_ANCHOR):
	@echo "🔑 Ensuring DNSSEC trust anchor -> /var/lib/unbound/root.key"
	@$(run_as_root) sh -c '\
		set -euo pipefail; \
		install -d -m 0770 -o root -g unbound /var/lib/unbound; \
		# Fast-path: if root.key exists AND stamp exists AND hashes match → skip \
		if [ -f /var/lib/unbound/root.key ] && [ -f "$(STAMP_UNBOUND_ANCHOR)" ]; then \
			if sha256sum /var/lib/unbound/root.key | awk "{print \$$1}" | cmp -s - "$(STAMP_UNBOUND_ANCHOR)"; then \
				echo "ℹ️ DNSSEC trust anchor up-to-date"; \
				exit 0; \
			fi; \
		fi; \
		echo "🔄 Updating DNSSEC trust anchor..."; \
		unbound-anchor -a /var/lib/unbound/root.key; \
		sha256sum /var/lib/unbound/root.key | awk "{print \$$1}" > "$(STAMP_UNBOUND_ANCHOR)"; \
		echo "🔐 DNSSEC trust anchor updated"; \
	'



# ------------------------------------------------------------
# Config deployment (pure)
# ------------------------------------------------------------
deploy-unbound-config: ensure-run-as-root
	@$(run_as_root) install -d -m 0755 /etc/unbound
	@echo "🔍 Validating Unbound configuration"
	@$(run_as_root) unbound-checkconf $(UNBOUND_CONF_SRC)
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_CONF_SRC),$(UNBOUND_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then echo "🔄 unbound.conf updated"; $(run_as_root) touch $(UNBOUND_RESTART_STAMP); fi

deploy-unbound-local-internal: ensure-run-as-root
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_LOCAL_INTERNAL_SRC),$(UNBOUND_LOCAL_INTERNAL_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then echo "🔄 local-internal.conf updated"; $(run_as_root) touch $(UNBOUND_RESTART_STAMP); fi

deploy-unbound-control-config: ensure-run-as-root
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_CONTROL_CONF_SRC),$(UNBOUND_CONTROL_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then echo "🔄 unbound-control.conf updated"; $(run_as_root) touch $(UNBOUND_RESTART_STAMP); fi

deploy-unbound-service: ensure-run-as-root
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_SERVICE_SRC),$(UNBOUND_SERVICE_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound.service updated"; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

install-unbound-systemd-dropin: ensure-run-as-root
	@$(run_as_root) install -d /etc/systemd/system/unbound.service.d
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_DROPIN_SRC),$(UNBOUND_DROPIN_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound systemd drop-in updated"; \
		$(run_as_root) systemctl daemon-reload; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# ------------------------------------------------------------
# Pure deploy (no restart, no runtime state)
# ------------------------------------------------------------
deploy-unbound: \
	deploy-unbound-sysctl \
	update-root-hints \
	ensure-dnssec-trust-anchor \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-service \
	deploy-unbound-control-config \
	install-unbound-systemd-dropin
	@echo "ℹ️ Unbound deployed (restart handled by enable-unbound)"

# ------------------------------------------------------------
# Single restart point
# ------------------------------------------------------------
enable-unbound: ensure-default-gateway ensure-run-as-root | deploy-unbound
	@if [ -f "$(UNBOUND_RESTART_STAMP)" ]; then \
		echo "🔄 Restarting Unbound"; \
		$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || true; \
		$(run_as_root) systemctl try-restart unbound || true; \
		$(run_as_root) rm -f $(UNBOUND_RESTART_STAMP); \
	else \
		echo "ℹ️ No restart needed"; \
	fi
	@echo "ℹ️ Waiting for Unbound..."; \
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do \
		if $(run_as_root) systemctl is-active --quiet unbound; then echo "✅ Unbound running"; exit 0; fi; \
		sleep 1; \
	done; \
	echo "❌ Unbound failed to start"; exit 1

# ------------------------------------------------------------
# Reset (runtime state only here)
# ------------------------------------------------------------
dns-reset-clean: ensure-run-as-root
	@echo "🧹 Clearing Unbound runtime state"
	@$(run_as_root) systemctl stop unbound || true
	@$(run_as_root) rm -rf /run/unbound /var/lib/unbound/* || true
	@$(run_as_root) install -d -m 0770 -o root -g unbound /var/lib/unbound

dns-reset: dns-reset-clean enable-unbound setup-unbound-control
	@echo "✅ DNS reset complete"

# ------------------------------------------------------------
# Remote control + status
# ------------------------------------------------------------
setup-unbound-control: ensure-run-as-root
	@$(run_as_root) scripts/unbound-setup-control.sh

unbound-status: ensure-run-as-root
	@$(run_as_root) systemctl status unbound --no-pager --lines=0

.PHONY: verify-internal-dns
verify-internal-dns:
	@echo "🔍 Verifying internal DNS (apt.bardi.ch)..."
	@if [ "$$(dig +short @10.89.12.4 apt.bardi.ch CNAME)" != "nas.bardi.ch." ]; then \
		echo "❌ DNS resolution failed"; exit 1; \
	fi
	@echo "✅ Internal DNS verified"