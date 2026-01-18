# mk/71_dns-warm.mk
# DNS cache warming automation (dns-warm-rotate)

BIN_DIR        ?= /usr/local/bin
SCRIPT_NAME    ?= dns-warm-rotate.sh
SCRIPT_PATH    ?= $(BIN_DIR)/$(SCRIPT_NAME)

DOMAINS_DIR    ?= /etc/dns-warm
DOMAINS_FILE   ?= $(DOMAINS_DIR)/domains.txt

STATE_DIR      ?= /var/lib/dns-warm
STATE_FILE     ?= $(STATE_DIR)/state.csv

SYSTEMD_DIR    ?= /etc/systemd/system
SERVICE        ?= dns-warm-rotate.service
TIMER          ?= dns-warm-rotate.timer
SERVICE_PATH   ?= $(SYSTEMD_DIR)/$(SERVICE)
TIMER_PATH     ?= $(SYSTEMD_DIR)/$(TIMER)

USER           ?= dnswarm
GROUP          ?= $(USER)
RESOLVER       ?= 127.0.0.1

# --- dns-warm domain policy (domain list generation) ---

DNS_WARM_POLICY_SRC := $(HOMELAB_DIR)/scripts/setup/dns-warm-update-domains.sh
DNS_WARM_POLICY_DST := /usr/local/bin/dns-warm-update-domains

.PHONY: install-dns-warm-policy update-dns-warm-domains

install-dns-warm-policy:
	@echo "📄 [make] Installing dns-warm domain policy script"
	@$(run_as_root) install -m 0755 $(DNS_WARM_POLICY_SRC) $(DNS_WARM_POLICY_DST)

# Fix parallel ordering
update-dns-warm-domains: dns-warm-install-script install-dns-warm-policy dns-warm-dirs
	@echo "🌐 [make] Updating dns-warm domain list"
	@$(run_as_root) $(DNS_WARM_POLICY_DST)
	@$(run_as_root) chown root:root $(DOMAINS_FILE)
	@$(run_as_root) chmod 0644 $(DOMAINS_FILE)

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

dns-warm-status: dns-warm-enable
	@$(run_as_root) systemctl status $(TIMER) --no-pager || true
	@$(run_as_root) systemctl status $(SERVICE) --no-pager || true

# Fix parallel ordering
dns-warm-enable: dns-warm-install-systemd
	@echo "Enabling dns-warm timer..."
	@$(run_as_root) systemctl enable --now $(TIMER)


dns-warm-disable:
	@echo "Disabling dns-warm timer..."
	-@$(run_as_root) systemctl disable --now $(TIMER)
	-@$(run_as_root) systemctl stop $(SERVICE)

dns-warm-start:
	@$(run_as_root) systemctl start $(SERVICE)

dns-warm-stop:
	@$(run_as_root) systemctl stop $(SERVICE)

dns-warm-uninstall: dns-warm-disable
	@echo "Removing dns-warm components..."
	@$(run_as_root) rm -f $(SERVICE_PATH) $(TIMER_PATH) $(SCRIPT_PATH) $(DNS_WARM_POLICY_DST)
	@$(run_as_root) rm -f $(STATE_FILE) $(DOMAINS_FILE)
	@$(run_as_root) systemctl daemon-reload

# -------------------------------------------------
# Internal helper targets
# -------------------------------------------------

dns-warm-create-user:
	@echo "Ensuring system user/group '$(USER)' exists..."
	@if ! getent group $(GROUP) >/dev/null 2>&1; then \
		$(run_as_root) groupadd --system $(GROUP); \
	fi
	@if ! id -u $(USER) >/dev/null 2>&1; then \
		$(run_as_root) useradd --system --no-create-home --shell /usr/sbin/nologin \
			-g $(GROUP) --comment "DNS cache warmer" $(USER); \
	fi

dns-warm-dirs:
	@$(run_as_root) mkdir -p $(DOMAINS_DIR) $(STATE_DIR)
	@$(run_as_root) chown -R $(USER):$(GROUP) $(DOMAINS_DIR) $(STATE_DIR)
	@$(run_as_root) chmod 750 $(STATE_DIR)

dns-warm-install-script: dns-warm-async-install
	@$(run_as_root) install -m 0755 scripts/$(SCRIPT_NAME) $(SCRIPT_PATH)
	@$(run_as_root) chown $(USER):$(GROUP) $(SCRIPT_PATH)
	@$(run_as_root) bash -n $(SCRIPT_PATH)

# Fix parallel ordering
dns-warm-install-systemd: dns-warm-install-script
	@echo "Installing systemd service and timer..."
	@$(run_as_root) sh -c 'printf "%s\n" \
"[Unit]" \
"Description=DNS cache warming job" \
"After=network.target" \
"" \
"[Service]" \
"Type=oneshot" \
"User=$(USER)" \
"Group=$(GROUP)" \
"ExecStart=/usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER)" \
"Nice=10" \
"WorkingDirectory=$(STATE_DIR)" \
"Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
"" \
"[Install]" \
"WantedBy=multi-user.target" \
> $(SERVICE_PATH)'
	@$(run_as_root) chmod 644 $(SERVICE_PATH)

	@$(run_as_root) sh -c 'printf "%s\n" \
"[Unit]" \
"Description=Run DNS cache warmer after previous run completes with wait time of 10s" \
"" \
"[Timer]" \
"OnBootSec=2min" \
"OnUnitInactiveSec=10s" \
"AccuracySec=30s" \
"Persistent=true" \
"" \
"[Install]" \
"WantedBy=timers.target" \
> $(TIMER_PATH)'
	@$(run_as_root) chmod 644 $(TIMER_PATH)

	@$(run_as_root) systemctl daemon-reload

# ------------------------------------------------------------
# Async DNS cache warmer (c-ares based)
# ------------------------------------------------------------
dns-warm-async: $(HOMELAB_DIR)/scripts/dns-warm-async.c prereqs
	@$(CC) -O2 -Wall -Wextra -o $@ $< -lcares

.PHONY: dns-warm-async-install
dns-warm-async-install: dns-warm-async
	@$(run_as_root) $(INSTALL_PATH)/install_if_changed.sh \
		dns-warm-async /usr/local/bin/dns-warm-async root root 0755
