# mk/71_dns-warm.mk
# DNS cache warming automation (dns-warm-rotate)

INSTALL_IF_CHANGED      := $(INSTALL_PATH)/install_if_changed.sh

ROTATE_SCRIPT_NAME      ?= dns-warm-rotate.sh
ROTATE_SCRIPT_PATH      ?= $(INSTALL_PATH)/$(ROTATE_SCRIPT_NAME)
ROTATE_SCRIPT_SRC_INST  := $(INSTALL_PATH)/$(ROTATE_SCRIPT_NAME)

DOMAINS_DIR    ?= /etc/dns-warm
DOMAINS_FILE   ?= $(DOMAINS_DIR)/domains.txt

DNS_WARM_STATE_DIR ?= /var/lib/dns-warm
STATE_FILE         ?= $(DNS_WARM_STATE_DIR)/state.csv

SERVICE        ?= dns-warm-rotate.service
TIMER          ?= dns-warm-rotate.timer
SERVICE_PATH   ?= $(SYSTEMD_DIR)/$(SERVICE)
TIMER_PATH     ?= $(SYSTEMD_DIR)/$(TIMER)

DNS_WARM_USER  := dnswarm
DNS_WARM_GROUP := $(DNS_WARM_USER)
RESOLVER       ?= 127.0.0.1
PER_RUN        ?= 2000

DNS_WARM_POLICY_SRC := $(MAKEFILE_DIR)scripts/dns-warm-update-domains.sh
DNS_WARM_POLICY_DST := $(INSTALL_PATH)/dns-warm-update-domains

.PHONY: install-dns-warm-policy update-dns-warm-domains prereqs-dns-warm-verify

install-dns-warm-policy: ensure-run-as-root
	@echo "📦 Deploying DNS warm policy script..."
	@$(run_as_root) $(INSTALL_IF_CHANGED) $(DNS_WARM_POLICY_SRC) $(DNS_WARM_POLICY_DST) root root 0755 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]

# Fix parallel ordering
update-dns-warm-domains: dns-warm-install-script install-dns-warm-policy dns-warm-dirs prereqs-dns-warm-verify ensure-run-as-root
	@echo "🌐 Updating dns-warm domain list"
	@$(run_as_root) $(DNS_WARM_POLICY_DST)
	@$(run_as_root) chown root:root $(DOMAINS_FILE)
	@$(run_as_root) chmod 0644 $(DOMAINS_FILE)
	@if [ -f $(STATE_FILE) ]; then $(run_as_root) chown $(DNS_WARM_USER):$(DNS_WARM_GROUP) $(STATE_FILE); fi

prereqs-dns-warm-verify:
	@command -v funzip >/dev/null || { \
		echo "❌ funzip missing (required for tranco list extraction)"; \
		echo "👉 Run: make prereqs"; \
		exit 1; \
	}

.PHONY: \
	dns-warm-install dns-warm-enable dns-warm-disable \
	dns-warm-uninstall dns-warm-start dns-warm-stop dns-warm-status \
	dns-warm-create-user dns-warm-dirs dns-warm-install-script \
	dns-warm-install-systemd

# -------------------------------------------------
# Public targets
# -------------------------------------------------

dns-warm-install: \
	dns-warm-create-user \
	dns-warm-dirs \
	install-dns-warm-policy \
	update-dns-warm-domains \
	dns-warm-install-script \
	dns-warm-install-systemd \
	dns-warm-enable

dns-warm-status: ensure-run-as-root
	@$(run_as_root) systemctl status $(TIMER) --no-pager || true
	@$(run_as_root) systemctl status $(SERVICE) --no-pager || true

# Fix parallel ordering
dns-warm-enable: dns-warm-install-systemd ensure-run-as-root
	@echo "⚙️ Enabling and starting dns-warm timer..."
	@$(run_as_root) systemctl unmask $(TIMER) > /dev/null 2>&1 || true
	@$(run_as_root) systemctl enable $(TIMER)
	@$(run_as_root) systemctl start $(TIMER)
	@$(run_as_root) systemctl is-active --quiet $(TIMER) && echo "✅ $(TIMER) active"

dns-warm-disable: ensure-run-as-root
	@echo "Disabling dns-warm timer..."
	-@$(run_as_root) systemctl disable --now $(TIMER)
	-@$(run_as_root) systemctl stop $(SERVICE)

dns-warm-start: ensure-run-as-root
	@$(run_as_root) systemctl start $(SERVICE)

dns-warm-stop: ensure-run-as-root
	@$(run_as_root) systemctl stop $(SERVICE)

dns-warm-uninstall: dns-warm-disable ensure-run-as-root
	@echo "Removing dns-warm components..."
	@$(run_as_root) rm -f $(SERVICE_PATH) $(TIMER_PATH) $(ROTATE_SCRIPT_PATH) $(DNS_WARM_POLICY_DST)
	@$(run_as_root) rm -f $(STATE_FILE) $(DOMAINS_FILE)
	@$(run_as_root) systemctl daemon-reload

# -------------------------------------------------
# Internal helper targets
# -------------------------------------------------

# This ensures that whenever we install dns-warm,
# the system identities are converged first.
dns-warm-create-user: enforce-groups
	@id -u $(DNS_WARM_USER) >/dev/null 2>&1 || { echo "❌ User $(DNS_WARM_USER) creation failed in groups.mk"; exit 1; }

dns-warm-dirs: ensure-run-as-root
	@$(run_as_root) mkdir -p $(DOMAINS_DIR) $(DNS_WARM_STATE_DIR)
	@$(run_as_root) chown -R $(DNS_WARM_USER):$(DNS_WARM_GROUP) $(DNS_WARM_STATE_DIR)
	@$(run_as_root) chown -R root:root $(DOMAINS_DIR)
	@$(run_as_root) chmod 750 $(DNS_WARM_STATE_DIR)

dns-warm-install-script: dns-warm-async-install ensure-run-as-root
	@$(run_as_root) $(INSTALL_IF_CHANGED) \
		$(ROTATE_SCRIPT_SRC_INST) $(ROTATE_SCRIPT_PATH) $(DNS_WARM_USER) $(DNS_WARM_GROUP) 0755 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]
	@$(run_as_root) bash -n $(ROTATE_SCRIPT_PATH)

# Fix parallel ordering
# mk/71_dns-warm.mk (Update the printf block)

dns-warm-install-systemd: dns-warm-install-script
	@echo "📦 Installing systemd service and timer..."
	@$(run_as_root) mkdir -p $(SYSTEMD_DIR)
	@$(run_as_root) printf "[Unit]\n\
Description=DNS cache warming job\n\
After=network.target\n\n\
[Service]\n\
Type=oneshot\n\
User=%s\n\
Group=%s\n\
ExecStart=/usr/bin/env bash %s %s %s\n\
Nice=10\n\
WorkingDirectory=%s\n\
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n\n\
[Install]\n\
WantedBy=multi-user.target\n" \
		"$(DNS_WARM_USER)" \
		"$(DNS_WARM_GROUP)" \
		"$(ROTATE_SCRIPT_PATH)" \
		"$(RESOLVER)" \
		"$(PER_RUN)" \
		"$(DNS_WARM_STATE_DIR)" | $(run_as_root) tee $(SERVICE_PATH) > /dev/null
	@$(run_as_root) chmod 644 $(SERVICE_PATH)
	@$(run_as_root) printf "[Unit]\n\
Description=Run DNS cache warmer every minute\n\n\
[Timer]\n\
OnBootSec=2min\n\
OnUnitInactiveSec=1m\n\
AccuracySec=1s\n\
Persistent=true\n\n\
[Install]\n\
WantedBy=timers.target\n" | $(run_as_root) tee $(TIMER_PATH) > /dev/null
	@$(run_as_root) chmod 644 $(TIMER_PATH)
	@$(run_as_root) systemctl daemon-reload

# ------------------------------------------------------------
# Async DNS cache warmer (c-ares based)
# ------------------------------------------------------------

DNS_WARM_ASYNC_SRC := $(MAKEFILE_DIR)scripts/dns-warm-async.c

.PHONY: dns-warm-async
dns-warm-async: $(DNS_WARM_ASYNC_SRC) prereqs
	@$(CC) -O2 -Wall -Wextra -o $@ $< -lcares

.PHONY: dns-warm-async-install
dns-warm-async-install: dns-warm-async ensure-run-as-root
	@$(run_as_root) $(INSTALL_IF_CHANGED) \
		dns-warm-async $(BIN_DIR)/dns-warm-async root root 0755 || [ $$? -eq $(INSTALL_IF_CHANGED_EXIT_CHANGED) ]