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
	systemctl enable --now $(TIMER)

dns-warm-disable:
	@echo "Disabling dns-warm timer..."
	-systemctl disable --now $(TIMER)
	-systemctl stop $(SERVICE)

dns-warm-start:
	systemctl start $(SERVICE)

dns-warm-stop:
	systemctl stop $(SERVICE)

dns-warm-status:
	systemctl status $(TIMER) --no-pager || true
	systemctl status $(SERVICE) --no-pager || true

dns-warm-uninstall: dns-warm-disable
	@echo "Removing dns-warm components..."
	rm -f $(SERVICE_PATH) $(TIMER_PATH) $(SCRIPT_PATH)
	rm -f $(STATE_FILE) $(DOMAINS_FILE)
	systemctl daemon-reload

# -------------------------------------------------
# Internal helper targets (also prefixed)
# -------------------------------------------------

dns-warm-create-user:
	@echo "Ensuring system user/group '$(USER)' exists..."
	@if ! getent group $(GROUP) >/dev/null 2>&1; then \
		groupadd --system $(GROUP); \
	fi
	@if ! id -u $(USER) >/dev/null 2>&1; then \
		useradd --system --no-create-home --shell /usr/sbin/nologin \
			-g $(GROUP) --comment "DNS cache warmer" $(USER); \
	fi

dns-warm-dirs:
	@echo "Creating runtime directories..."
	mkdir -p $(DOMAINS_DIR) $(STATE_DIR)
	chown -R $(USER):$(GROUP) $(DOMAINS_DIR) $(STATE_DIR)
	chmod 750 $(STATE_DIR)

dns-warm-install-script:
	@echo "Installing dns-warm script..."
	install -m 0755 scripts/$(SCRIPT_NAME) $(SCRIPT_PATH)
	chown $(USER):$(GROUP) $(SCRIPT_PATH)
	@bash -n $(SCRIPT_PATH)

dns-warm-install-domains:
	@echo "Ensuring domains file exists..."
	@if [ ! -f $(DOMAINS_FILE) ]; then \
		install -m 644 /dev/null $(DOMAINS_FILE); \
		chown $(USER):$(GROUP) $(DOMAINS_FILE); \
	fi

dns-warm-install-systemd:
	@echo "Installing systemd service and timer..."
	printf '%s\n' \
'[Unit]' \
'Description=DNS cache warming job' \
'After=network.target' \
'' \
'[Service]' \
'Type=oneshot' \
'User=$(USER)' \
'Group=$(GROUP)' \
'ExecStart=/usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER)' \
'Nice=10' \
'RuntimeMaxSec=55' \
'WorkingDirectory=$(STATE_DIR)' \
'Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
'' \
'[Install]' \
'WantedBy=multi-user.target' \
> $(SERVICE_PATH)
	chmod 644 $(SERVICE_PATH)

	printf '%s\n' \
'[Unit]' \
'Description=Run DNS cache warmer every minute' \
'' \
'[Timer]' \
'OnBootSec=1min' \
'OnUnitActiveSec=1min' \
'AccuracySec=1s' \
'' \
'[Install]' \
'WantedBy=timers.target' \
> $(TIMER_PATH)
	chmod 644 $(TIMER_PATH)

	systemctl daemon-reload
