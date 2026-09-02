# mk/71_dns-warm.mk
# DNS cache warming automation (dns-warm-rotate)

ROTATE_SCRIPT_NAME      ?= dns-warm-rotate.sh
ROTATE_SCRIPT_PATH      ?= $(INSTALL_PATH)/$(ROTATE_SCRIPT_NAME)
ROTATE_SCRIPT_SRC := $(REPO_ROOT)/scripts/$(ROTATE_SCRIPT_NAME)

DOMAINS_DIR     ?= /etc/dns-warm
DOMAINS_FILE    ?= $(DOMAINS_DIR)/domains.txt

DNS_WARM_STATE_DIR ?= /var/lib/dns-warm
STATE_FILE         ?= $(DNS_WARM_STATE_DIR)/state.csv

SERVICE         ?= dns-warm-rotate.service
TIMER           ?= dns-warm-rotate.timer
SERVICE_PATH    ?= $(SYSTEMD_DIR)/$(SERVICE)
TIMER_PATH      ?= $(SYSTEMD_DIR)/$(TIMER)

DNS_WARM_USER  := dnswarm
DNS_WARM_GROUP := $(DNS_WARM_USER)

RESOLVER       ?= $(NAS_LAN_IP)
RESOLVER_IP6   ?= $(NAS_LAN_IP6)
PER_RUN        ?= 2000

DNS_WARM_POLICY_SRC := $(REPO_ROOT)/scripts/dns-warm-update-domains.sh
DNS_WARM_POLICY_DST := $(INSTALL_PATH)/dns-warm-update-domains

.PHONY: install-dns-warm-policy update-dns-warm-domains prereqs-dns-warm-verify \
    dns-warm-install dns-warm-enable dns-warm-disable \
    dns-warm-uninstall dns-warm-start dns-warm-stop dns-warm-status \
    dns-warm-create-user dns-warm-dirs dns-warm-install-script \
    dns-warm-install-systemd dns-warm-async dns-warm-health dns-warm-now

install-dns-warm-policy: install-all
	@echo "📦 Deploying DNS warm policy script..."
	@$(call install_file,$(DNS_WARM_POLICY_SRC),$(DNS_WARM_POLICY_DST),root,root,0755)

# Fix parallel ordering
update-dns-warm-domains: dns-warm-install-script install-dns-warm-policy dns-warm-dirs prereqs-dns-warm-verify
	@echo "🌐 Updating dns-warm domain list"
	@$(run_as_root) sh -c '\
		"$(DNS_WARM_POLICY_DST)" && \
		chown root:root "$(DOMAINS_FILE)" && \
		chmod 0644 "$(DOMAINS_FILE)" && \
		if [ -f "$(STATE_FILE)" ]; then chown $(DNS_WARM_USER):$(DNS_WARM_GROUP) "$(STATE_FILE)"; fi'

prereqs-dns-warm-verify:
	@command -v funzip >/dev/null || { \
		echo "❌ funzip missing (required for tranco list extraction)"; \
		echo "➡️ Run: make prereqs"; \
		exit 1; \
	}

# Install missing tools for dns-warm
prereqs-dns-warm-install: prereqs-run
	$(call apt_install, funzip, unzip, libc-ares-dev)

# Wire install ➡️ verify
prereqs-dns-warm: prereqs-dns-warm-install prereqs-dns-warm-verify

# -------------------------------------------------
# Public targets
# -------------------------------------------------

dns-warm-install: \
    prereqs-dns-warm \
    dns-warm-create-user \
    dns-warm-dirs \
    install-dns-warm-policy \
    update-dns-warm-domains \
    dns-warm-install-script \
    dns-warm-install-systemd \
    dns-warm-enable

dns-warm-status:
	@$(run_as_root) sh -c 'systemctl status $(TIMER) --no-pager || true; systemctl status $(SERVICE) --no-pager || true'

dns-warm-enable: dns-warm-install-systemd
	@echo "⚙️ Enabling and starting dns-warm timer..."
	@$(run_as_root) sh -c ' \
		systemctl unmask $(TIMER) > /dev/null 2>&1 || true && \
		systemctl enable $(TIMER) && \
		systemctl start $(TIMER) && \
		systemctl is-active --quiet $(TIMER) && echo "✅ $(TIMER) active" \
	'

dns-warm-disable:
	@echo "Disabling dns-warm timer..."
	-@$(run_as_root) sh -c 'systemctl disable --now $(TIMER) && systemctl stop $(SERVICE)'

dns-warm-start:
	@$(run_as_root) systemctl start $(SERVICE)

dns-warm-stop:
	@$(run_as_root) systemctl stop $(SERVICE)

dns-warm-uninstall: dns-warm-disable
	@echo "Removing dns-warm components..."
	@$(run_as_root) sh -c ' \
		rm -f $(SERVICE_PATH) $(TIMER_PATH) $(ROTATE_SCRIPT_PATH) $(DNS_WARM_POLICY_DST) && \
		rm -f $(STATE_FILE) $(DOMAINS_FILE) && \
		systemctl daemon-reload \
	'

# -------------------------------------------------
# Internal helper targets
# -------------------------------------------------

# This ensures that whenever we install dns-warm,
# the system identities are converged first.
dns-warm-create-user: enforce-groups
	@id -u $(DNS_WARM_USER) >/dev/null 2>&1 || { echo "❌ User $(DNS_WARM_USER) creation failed in groups.mk"; exit 1; }

dns-warm-dirs:
	@$(run_as_root) sh -c '\
		install -d -m 0750 -o $(DNS_WARM_USER) -g $(DNS_WARM_GROUP) $(DNS_WARM_STATE_DIR) && \
		install -d -m 0755 -o root -g root $(DOMAINS_DIR)'

dns-warm-install-script: dns-warm-async-install install-all
	@$(call install_file,$(ROTATE_SCRIPT_SRC),$(ROTATE_SCRIPT_PATH),$(DNS_WARM_USER),$(DNS_WARM_GROUP),0755)
	@$(run_as_root) bash -n $(ROTATE_SCRIPT_PATH)

dns-warm-install-systemd: dns-warm-install-script
	@echo "📦 Checking systemd service and timer..."
	@$(run_as_root) sh -c '\
		mkdir -p "$(SYSTEMD_DIR)" && \
		TMP_SVC=$$(mktemp) && TMP_TMR=$$(mktemp) && \
		printf "[Unit]\nDescription=DNS cache warming job\nAfter=network.target\n\n[Service]\nType=oneshot\nUser=%s\nGroup=%s\nExecStart=/usr/bin/env bash %s %s %s %s\nNice=10\nWorkingDirectory=%s\nEnvironment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n\n[Install]\nWantedBy=multi-user.target\n" \
			"$(DNS_WARM_USER)" \
			"$(DNS_WARM_GROUP)" \
			"$(ROTATE_SCRIPT_PATH)" \
			"$(RESOLVER)" \
			"$(PER_RUN)" \
			"$(DNS_WARM_STATE_DIR)" > "$$TMP_SVC" && \
		printf "[Unit]\nDescription=Run DNS cache warmer every minute\n\n[Timer]\nOnBootSec=2min\nOnUnitInactiveSec=1m\nAccuracySec=1s\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n" > "$$TMP_TMR" && \
		CHANGED=0 && \
		if ! cmp -s "$$TMP_SVC" "$(SERVICE_PATH)"; then \
			cp "$$TMP_SVC" "$(SERVICE_PATH)" && chmod 644 "$(SERVICE_PATH)" && CHANGED=1; \
		fi && \
		if ! cmp -s "$$TMP_TMR" "$(TIMER_PATH)"; then \
			cp "$$TMP_TMR" "$(TIMER_PATH)" && chmod 644 "$(TIMER_PATH)" && CHANGED=1; \
		fi && \
		rm -f "$$TMP_SVC" "$$TMP_TMR" && \
		if [ "$$CHANGED" -eq 1 ]; then \
			echo "🔄 Systemd units updated, reloading daemon..." && \
			systemctl daemon-reload; \
		fi'

# ------------------------------------------------------------
# Async DNS cache warmer (c-ares based)
# ------------------------------------------------------------

DNS_WARM_ASYNC_SRC := $(REPO_ROOT)/scripts/dns-warm-async.c
DNS_WARM_ASYNC_BIN := $(INSTALL_PATH)/dns-warm-async

$(DNS_WARM_ASYNC_BIN): $(DNS_WARM_ASYNC_SRC) prereqs-ok
	@$(run_as_root) $(CC) -O2 -Wall -Wextra -o $@ $< -lcares

dns-warm-async: $(DNS_WARM_ASYNC_BIN)

dns-warm-async-install: $(DNS_WARM_ASYNC_BIN)
	@$(run_as_root) chmod 0755 $(DNS_WARM_ASYNC_BIN)

dns-warm-health:
	@echo "🔍 DNS-warm health check"
	@if $(run_as_root) systemctl is-active --quiet $(TIMER); then \
		echo "✅ Timer active"; \
	else \
		echo "❌ Timer inactive"; \
	fi
	@if $(run_as_root) systemctl is-active --quiet $(SERVICE); then \
		echo "✅ Service healthy (oneshot, currently running)"; \
	else \
		echo "✅ Service healthy (oneshot, currently not running)"; \
	fi
	@if [ -s $(DOMAINS_FILE) ]; then \
		age=$$(( $$(date +%s) - $$(stat -c %Y $(DOMAINS_FILE)) )); \
		count=$$(wc -l < $(DOMAINS_FILE)); \
		echo "✅ Domain list present: Entries: $$count, Age: $$age seconds"; \
	else \
		echo "❌ Domain list missing or empty"; \
	fi

	@if $(run_as_root) test -f $(STATE_FILE); then \
		echo "✅ State file present : $(STATE_FILE)"; \
		$(run_as_root) stat -c '   • Size: %s bytes' $(STATE_FILE); \
		$(run_as_root) stat -c '   • Updated: %y' $(STATE_FILE); \
	else \
		echo "⚠️ State file missing (rotate job may not have run yet)"; \
	fi
	@if $(run_as_root) dig +time=1 +tries=1 -p $(UNBOUND_PORT) @127.0.0.1 $(DOMAIN) >/dev/null 2>&1; then \
			echo "✅ Resolver IPv4 (Unbound :$(UNBOUND_PORT)): reachable"; \
	else \
			echo "❌ Resolver IPv4 (Unbound :$(UNBOUND_PORT)): unreachable"; \
	fi

	@if [ -n "$(RESOLVER_IP6)" ]; then \
		$(run_as_root) sh -c 'err=$$(dig +time=1 +tries=1 @$(RESOLVER_IP6) $(DOMAIN) 2>&1 >/dev/null || true); \
		if [ -z "$$err" ]; then \
			echo "✅ Resolver IPv6 ($(RESOLVER_IP6)): reachable"; \
		else \
			echo "❌ Resolver IPv6 ($(RESOLVER_IP6)): unreachable"; \
			test -z "$(VERBOSE)" || echo "$$err"; \
		fi'; \
	else \
		test -z "$(VERBOSE)" || echo "ℹ️ Resolver IPv6 not configured; skipping"; \
	fi
	@echo "✅ DNS-warm health check complete"

dns-warm-now: dns-warm-install-systemd update-dns-warm-domains dns-warm-start dns-warm-health
	@echo "📜 Last warm run:"
	@journalctl -u $(SERVICE) -n 1 --no-pager || true
	@echo "✅ dns-warm-now complete"