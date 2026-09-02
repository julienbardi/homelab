# mk/60_unbound.mk — Unbound orchestration (config-only, pure DAG)

UNBOUND_RESTART_STAMP := $(STAMP_DIR_ROOT)/unbound.restart
STAMP_UNBOUND_ANCHOR  := $(STAMP_DIR_ROOT)/unbound_anchor.sha256

SYSCTL_UNBOUND_SRC := $(REPO_ROOT)/config/sysctl/99-unbound-buffers.conf
SYSCTL_UNBOUND_DST := /etc/sysctl.d/99-unbound-buffers.conf

UNBOUND_CONF_SRC := $(REPO_ROOT)/config/unbound/unbound.conf
UNBOUND_CONF_DST := /etc/unbound/unbound.conf

UNBOUND_LOCAL_INTERNAL_SRC := $(REPO_ROOT)/config/unbound/unbound.conf.d/local-internal.conf
UNBOUND_LOCAL_INTERNAL_DST := /etc/unbound/unbound.conf.d/local-internal.conf

.PHONY: \
	deploy-unbound \
	deploy-unbound-sysctl \
	fetch-root-hints \
	update-root-hints \
	ensure-dnssec-trust-anchor \
	deploy-unbound-config \
	deploy-unbound-local-internal \
	unbound-health

# ------------------------------------------------------------
# Sysctl (safe: kernel tuning only)
# ------------------------------------------------------------
deploy-unbound-sysctl: install-all
	@changed=0; rc=0; \
	$(call install_file,$(SYSCTL_UNBOUND_SRC),$(SYSCTL_UNBOUND_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 sysctl config updated — reloading"; \
		$(run_as_root) $(SYSCTL_BIN) --system >/dev/null; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# ------------------------------------------------------------
# Root hints (pure data)
# ------------------------------------------------------------

fetch-root-hints: install-all
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "🌐 Downloading latest root hints from internic.net"; fi; \
	temp_hints="$$(mktemp)"; \
	curl -sSL -o "$$temp_hints" https://www.internic.net/domain/named.root; \
	if grep -q "NS.*A.ROOT-SERVERS.NET." "$$temp_hints"; then \
		rc=0; \
		$(call install_file,"$$temp_hints",$(REPO_ROOT)/config/unbound/root.hints,"$(USER_UID)","$(USER_GID)",0664) || rc=$$?; \
		rm -f "$$temp_hints"; \
		case "$${rc:-0}" in \
			0) \
				if [ "$(VERBOSE)" -ge "1" ]; then echo "ℹ️ root.hints is already up to date in repository source"; fi; \
				;; \
			$(INSTALL_IF_CHANGED_EXIT_CHANGED)) \
				echo "✅ root.hints successfully verified and updated in repository source"; \
				;; \
			*) exit "$$rc" ;; \
		esac; \
	else \
		rm -f "$$temp_hints"; \
		echo "❌ Downloaded root hints validation failed — source file left untouched"; \
		exit 1; \
	fi

update-root-hints: install-all fetch-root-hints
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "🌐 Installing static root hints"; fi; \
	$(run_as_root) install -d -m 0750 -o root -g unbound /var/lib/unbound; \
	rc=0; \
	$(call install_file,$(REPO_ROOT)/config/unbound/root.hints,/var/lib/unbound/root.hints,root,unbound,0664) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) \
			echo "🔄 root.hints updated — scheduling restart. 👉 Run 'make deploy-unbound' to apply changes"; \
			$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
			;; \
		*) exit "$$rc" ;; \
	esac

# ------------------------------------------------------------
# Trust anchor (stamp-driven, no service control)
# ------------------------------------------------------------
ensure-dnssec-trust-anchor: $(STAMP_UNBOUND_ANCHOR)
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
# Config deployment
# ------------------------------------------------------------
deploy-unbound-config: update-root-hints deploy-unbound-local-internal install-all
	@$(run_as_root) install -d -m 0755 /etc/unbound /etc/unbound/unbound.conf.d
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_CONF_SRC),$(UNBOUND_CONF_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 unbound.conf updated — scheduling restart"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

deploy-unbound-local-internal: install-all
	@changed=0; rc=0; \
	$(call install_file,$(UNBOUND_LOCAL_INTERNAL_SRC),$(UNBOUND_LOCAL_INTERNAL_DST),root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) changed=1 ;; \
		*) exit "$$rc" ;; \
	esac; \
	if [ $$changed -eq 1 ]; then \
		echo "🔄 local-internal.conf updated — scheduling restart"; \
		$(run_as_root) touch $(UNBOUND_RESTART_STAMP); \
	fi

# ------------------------------------------------------------
# Unbound health (read-only, no lifecycle control)
# ------------------------------------------------------------
unbound-health:
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "🔍 Unbound health check"; fi; \
	\
	# 1. Process check \
	if pgrep -x unbound >/dev/null 2>&1; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "✅ process: unbound running"; fi; \
	else \
		echo "❌ process: unbound NOT running"; \
		exit 1; \
	fi; \
	\
	# 2. Control socket check \
	if $(run_as_root) unbound-control -c /etc/unbound/unbound.conf status >/dev/null 2>&1; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "✅ control socket: responding"; fi; \
	else \
		echo "❌ control socket: not responding"; \
		exit 1; \
	fi; \
	\
	# 3.DNS functional check (internal) \
	if [ "$$(dig +short @127.0.0.1 -p $(UNBOUND_PORT) $(DOMAIN) CNAME)" = "" ]; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "✅ internal DNS OK"; fi; \
	else \
		echo "❌ internal DNS FAILED"; \
		exit 1; \
	fi; \
	\
	# 4. DNS functional check (external) \
	if dig +short @127.0.0.1 cloudflare.com A >/dev/null 2>&1; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "✅ external DNS OK"; fi; \
	else \
		echo "❌ external DNS FAILED"; \
		exit 1; \
	fi; \
	\
	if [ "$(VERBOSE)" -ge "1" ]; then echo "🎉 Unbound health: ALL CHECKS PASSED"; fi

.PHONY: enable-homelab-unbound
enable-homelab-unbound: deploy-homelab-unbound-service
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "🚀 Enabling homelab-unbound.service"; fi; \
	message=""; \
	if ! systemctl is-enabled --quiet homelab-unbound.service 2>/dev/null; then \
		$(run_as_root) systemctl enable homelab-unbound.service; \
		message="enabled"; \
	else \
		message="already enabled"; \
	fi; \
	if ! systemctl is-active --quiet homelab-unbound.service; then \
		$(run_as_root) sh -c '[ -f /etc/unbound/unbound_server.pem ] || unbound-control-setup -d /etc/unbound'; \
		$(run_as_root) systemctl start homelab-unbound.service; \
		message="$$message and started"; \
	else \
		message="$$message and already active"; \
	fi; \
	if [ "$$message" != "already enabled and already active" -o "$(VERBOSE)" -ge "1" ]; then echo "🟢 homelab-unbound $$message"; fi \

deploy-homelab-unbound-service: install-all
	@rc=0; \
	$(call install_file,$(REPO_ROOT)/config/systemd/homelab-unbound.service,/etc/systemd/system/homelab-unbound.service,root,root,0644) || rc=$$?; \
	case "$${rc:-0}" in \
		0) ;; \
		$(INSTALL_IF_CHANGED_EXIT_CHANGED)) \
			echo "🔄 homelab-unbound.service unit updated — reloading systemd context"; \
			$(run_as_root) sh -c 'systemctl daemon-reload && touch "$(UNBOUND_RESTART_STAMP)"' \
			;; \
		*) exit "$$rc" ;; \
	esac

deploy-unbound: deploy-unbound-config deploy-homelab-unbound-service
	@if [ -f "$(UNBOUND_RESTART_STAMP)" ]; then \
		echo "🔄 Executing deferred restart for homelab-unbound.service due to configuration drift"; \
		$(run_as_root) sh -c '[ -f /etc/unbound/unbound_server.pem ] || unbound-control-setup -d /etc/unbound'; \
		$(run_as_root) sh -c 'systemctl restart homelab-unbound.service && rm -f "$(UNBOUND_RESTART_STAMP)"'; \
	else \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "🟢 Unbound configuration layout holds no drift"; fi;\
	fi

.PHONY: enable-unbound
enable-unbound: enable-homelab-unbound

.PHONY: verify-internal-dns
verify-internal-dns:
	@if [ "$(VERBOSE)" -ge "1" ]; then echo "🔍 Verifying internal DNS"; fi; \
	if [ "$$(dig +short @127.0.0.1 -p $(UNBOUND_PORT) $(DOMAIN) CNAME)" = "" ]; then \
		if [ "$(VERBOSE)" -ge "1" ]; then echo "✅ internal DNS OK"; fi; \
	else \
		echo "❌ internal DNS FAILED"; \
		exit 1; \
	fi