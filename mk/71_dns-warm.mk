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

.PHONY: \
	dns-warm-install dns-warm-enable dns-warm-disable \
	dns-warm-uninstall dns-warm-start dns-warm-stop dns-warm-status \
	dns-warm-create-user dns-warm-dirs dns-warm-install-script \
	dns-warm-install-domains dns-warm-install-systemd

# -------------------------------------------------
# Public targets
# -------------------------------------------------

dns-warm-install: \
	dns-warm-create-user \
	dns-warm-dirs \
	dns-warm-install-script \
	dns-warm-install-domains \
	dns-warm-install-systemd
	@echo "dns-warm installed. Enable with: make dns-warm-enable"

dns-warm-enable:
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

dns-warm-status:
	@$(run_as_root) systemctl status $(TIMER) --no-pager || true
	@$(run_as_root) systemctl status $(SERVICE) --no-pager || true

dns-warm-uninstall: dns-warm-disable
	@echo "Removing dns-warm components..."
	@$(run_as_root) rm -f $(SERVICE_PATH) $(TIMER_PATH) $(SCRIPT_PATH)
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

dns-warm-install-script:
	@$(run_as_root) install -m 0755 scripts/$(SCRIPT_NAME) $(SCRIPT_PATH)
	@$(run_as_root) chown $(USER):$(GROUP) $(SCRIPT_PATH)
	@$(run_as_root) bash -n $(SCRIPT_PATH)

dns-warm-install-domains:
	@echo "Ensuring domains file exists..."
	@if [ ! -f $(DOMAINS_FILE) ]; then \
		$(run_as_root) install -m 644 /dev/null $(DOMAINS_FILE); \
		$(run_as_root) chown $(USER):$(GROUP) $(DOMAINS_FILE); \
	fi

dns-warm-install-systemd:
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
"Description=Run DNS cache warmer after previous run completes" \
"" \
"[Timer]" \
"OnBootSec=2min" \
"OnUnitInactiveSec=10min" \
"AccuracySec=30s" \
"" \
"[Install]" \
"WantedBy=timers.target" \
> $(TIMER_PATH)'
	@$(run_as_root) chmod 644 $(TIMER_PATH)

	@$(run_as_root) systemctl daemon-reload
