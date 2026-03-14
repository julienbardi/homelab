# ============================================================
# mk/60_unbound.mk — Unbound orchestration
# ============================================================

UNBOUND_RESTART_STAMP := $(STAMP_DIR)/unbound.restart

SYSCTL_UNBOUND_SRC := $(MAKEFILE_DIR)config/sysctl/99-unbound-buffers.conf
SYSCTL_UNBOUND_DST := /etc/sysctl.d/99-unbound-buffers.conf

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
		$(run_as_root) /sbin/sysctl --system >/dev/null; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

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
	ensure-dnssec-trust-anchor \
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

enable-unbound: ensure-run-as-root \
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
		$(call apt_install,unbound,unbound) \
	fi
	@$(run_as_root) systemctl enable --now unbound >/dev/null 2>&1 || true
	@echo "✅ Unbound installed and enabled"

remove-pkg-unbound:
	$(call apt_remove,unbound)

# --- Deployment ---
UNBOUND_CONF_SRC := $(MAKEFILE_DIR)config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_CONTROL_CONF_SRC := $(MAKEFILE_DIR)config/unbound/unbound-control.conf
UNBOUND_CONTROL_CONF_DST := /etc/unbound/unbound-control.conf

assert-unbound-tools:
	@PATH=/usr/sbin:/sbin:$$PATH command -v unbound >/dev/null || \
		( echo "❌ unbound not installed. Run: make prereqs"; exit 1 )
	@command -v dig >/dev/null || \
		( echo "❌ dig not installed. Run: make prereqs"; exit 1 )
	@PATH=/usr/sbin:/sbin:$$PATH command -v unbound-control >/dev/null || \
		( echo "❌ unbound-control not installed. Run: make prereqs"; exit 1 )

# --- Root hints ---
update-root-hints: ensure-run-as-root
	@echo "🌐 Updating root hints -> /var/lib/unbound/root.hints"
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
ensure-dnssec-trust-anchor: ensure-run-as-root
	@echo "🔑 Ensuring DNSSEC trust anchor -> /var/lib/unbound/root.key"
	@$(run_as_root) mkdir -p /var/lib/unbound
	@if [ ! -f /var/lib/unbound/root.key ]; then \
		$(run_as_root) unbound-anchor -a /tmp/root.key; \
		$(run_as_root) install -m 0644 -o root -g unbound /tmp/root.key /var/lib/unbound/root.key; \
	fi
	@echo "✅ root key present"

deploy-unbound-config: ensure-run-as-root update-root-hints ensure-dnssec-trust-anchor rotate
	@$(run_as_root) install -d -m 0755 /etc/unbound
	@changed=0; \
	rc=0; \
	$(call install_file,$(UNBOUND_CONF_SRC),$(UNBOUND_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	$(run_as_root) su -s /bin/sh unbound -c "cd /tmp && unbound-checkconf $(UNBOUND_CONF_DST)" || { echo "❌ invalid config"; exit 1; }; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

deploy-unbound-control-config: ensure-run-as-root
	@changed=0; \
	rc=0; \
	$(call install_file,$(UNBOUND_CONTROL_CONF_SRC),$(UNBOUND_CONTROL_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound-control.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

UNBOUND_SERVICE_SRC := $(MAKEFILE_DIR)config/systemd/unbound.service
UNBOUND_SERVICE_DST := /etc/systemd/system/unbound.service

deploy-unbound-service: ensure-run-as-root
	@changed=0; \
	rc=0; \
	$(call install_file,$(UNBOUND_SERVICE_SRC),$(UNBOUND_SERVICE_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound.service updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
		$(run_as_root) systemctl daemon-reload; \
	fi

UNBOUND_LOCAL_INTERNAL_SRC := $(MAKEFILE_DIR)config/unbound/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

deploy-unbound-local-internal: ensure-run-as-root
	@changed=0; \
	rc=0; \
	$(call install_file,$(UNBOUND_LOCAL_INTERNAL_SRC),$(UNBOUND_LOCAL_INTERNAL_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	$(run_as_root) su -s /bin/sh unbound -c "cd /tmp && unbound-checkconf $(UNBOUND_CONF_DST)" || { echo "❌ invalid config"; exit 1; }; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 local-internal.conf updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# --- Systemd drop-in for fixing /run/unbound.ctl ownership ---
UNBOUND_DROPIN_SRC := $(MAKEFILE_DIR)config/systemd/unbound.service.d/99-fix-unbound-ctl.conf
UNBOUND_DROPIN_DST := /etc/systemd/system/unbound.service.d/99-fix-unbound-ctl.conf

install-unbound-systemd-dropin: ensure-run-as-root
	@$(run_as_root) install -d /etc/systemd/system/unbound.service.d
	@changed=0; \
	rc=0; \
	$(call install_file,$(UNBOUND_DROPIN_SRC),$(UNBOUND_DROPIN_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound systemd drop-in updated"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
		$(run_as_root) systemctl daemon-reload; \
	fi

deploy-unbound:
	dns-preflight \
	install-pkg-unbound \
	deploy-unbound-sysctl \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	deploy-unbound-service \
	deploy-unbound-control-config
	@echo "ℹ️ Unbound deployed (restart handled by enable-unbound)"

# --- Remote control ---
setup-unbound-control: ensure-run-as-root
	@$(run_as_root) scripts/unbound-setup-control.sh

dns-health: assert-unbound-tools assert-unbound-control dns-runtime
	@$(run_as_root) scripts/unbound-health.sh

reset-unbound-control: ensure-run-as-root
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

ROTATE_ROOTKEYS := $(INSTALL_PATH)/rotate-unbound-rootkeys.sh

rotate: ensure-run-as-root $(ROTATE_ROOTKEYS)
	@echo "🔄 Refreshing DNSSEC trust anchors"
	@$(run_as_root) $(ROTATE_ROOTKEYS)

dns-bench:
	@set -eu; \
	echo "🌐 Downloading OpenDNS top domains list..."; \
	raw=/tmp/opendns-top-domains.raw.txt; \
	qry=/tmp/opendns-top-domains.qry.txt; \
	tmp=/tmp/opendns-top-domains.slice.txt; \
	curl -fsSL -o "$$raw" https://raw.githubusercontent.com/opendns/public-domain-lists/master/opendns-top-domains.txt; \
	awk 'NF==0{next} $$1 ~ /^[0-9]+$$/ {d=$$2; next} {d=$$1} \
		 d ~ /^[A-Za-z0-9._-]+(\.[A-Za-z0-9._-]+)+$$/ {print d " A"}' "$$raw" >"$$qry"; \
	total=$$(wc -l <"$$qry" | tr -d ' '); \
	echo "ℹ️  Prepared $$total queries"; \
	for n in 10 100 1000; do \
		echo "⚡ Priming first $$n domains (parallel, best-effort)…"; \
		head -n $$n "$$qry" >"$$tmp"; \
		xargs -a "$$tmp" -P $(N_WORKERS) -n 2 \
			sh -c 'dig @127.0.0.1 -p 5335 "$$1" "$$2" +tries=1 +time=1 >/dev/null 2>&1 || true' _; \
		echo "🔥 dnsperf against Unbound (127.0.0.1:5335), $$n domains…"; \
		dnsperf -s 127.0.0.1 -p 5335 -d "$$tmp" -l 10 -q 200 \
			| grep -v '^\[Timeout\]'; \
	done; \
	rm -f "$$tmp"; \
	echo "✅ DNS benchmark complete"


dns-runtime: \
	enable-systemd \
	install-unbound-systemd-dropin \
	deploy-unbound-sysctl \
	dnsdist \
	dns-warm-install \
	dns-warm-enable
	@echo "⚙️ DNS runtime helpers ensured (dnsdist + dns-warm)"

# --- Reset + bootstrap ---
dns-reset-clean: ensure-run-as-root
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

unbound-status: ensure-run-as-root
	@$(run_as_root) systemctl status unbound --no-pager --lines=0