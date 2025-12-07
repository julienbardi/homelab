# 71_dns-warm.mk - self-contained installer for DNS warm rotate (no heredocs)
# Usage:
#   sudo make -f mk/71_dns-warm.mk install USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk enable USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk disable USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk uninstall USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk test USER=dnswarm (broken)

BIN_DIR ?= /usr/local/bin
SCRIPT_NAME ?= dns-warm-rotate.sh
SCRIPT_PATH ?= $(BIN_DIR)/$(SCRIPT_NAME)
DOMAINS_DIR ?= /etc/dns-warm
DOMAINS_FILE ?= $(DOMAINS_DIR)/domains.txt
STATE_DIR ?= /var/lib/dns-warm
STATE_FILE ?= $(STATE_DIR)/state.csv
SYSTEMD_DIR ?= /etc/systemd/system
SERVICE ?= dns-warm-rotate.service
TIMER ?= dns-warm-rotate.timer
SERVICE_PATH ?= $(SYSTEMD_DIR)/$(SERVICE)
TIMER_PATH ?= $(SYSTEMD_DIR)/$(TIMER)
USER ?= dnswarm
GROUP ?= $(USER)
RESOLVER ?= 127.0.0.1

.PHONY: install enable disable uninstall start stop status test create-user dirs \
		install-script install-domains install-systemd install-deps

all: install

install: install-deps create-user dirs install-script install-domains install-systemd
	@echo "Installed dns-warm components. Run 'sudo make -f mk/71_dns-warm.mk enable USER=$(USER)' to enable timer."

install-deps:
	@echo "Installing optional dependencies (pup, python bs4/requests, dnsutils)..."
	@if command -v apt-get >/dev/null 2>&1; then \
		apt-get update && apt-get install -y pup python3-requests python3-bs4 dnsutils || true; \
	else \
		echo "Please install 'pup', 'python3-requests', 'python3-bs4', and 'dnsutils' manually for full support."; \
	fi

create-user:
	@echo "Creating system user/group '$(USER)' if missing..."
	@if ! getent group $(GROUP) >/dev/null 2>&1; then \
		groupadd --system $(GROUP) || true; \
	fi; \
	if ! id -u $(USER) >/dev/null 2>&1; then \
		useradd --system --no-create-home --shell /usr/sbin/nologin -g $(GROUP) --comment "dns warm rotate" $(USER) || true; \
	fi

dirs:
	@echo "Creating directories and setting ownership..."
	mkdir -p $(BIN_DIR)
	mkdir -p $(DOMAINS_DIR)
	mkdir -p $(STATE_DIR)
	chown -R $(USER):$(GROUP) $(DOMAINS_DIR) $(STATE_DIR) || true
	chmod 750 $(STATE_DIR) || true

install-script:
	@echo "Installing warming script to $(SCRIPT_PATH)..."
	@if [ -f ./scripts/$(SCRIPT_NAME) ]; then \
		install -m 755 -D ./scripts/$(SCRIPT_NAME) $(SCRIPT_PATH); \
		chown $(USER):$(GROUP) $(SCRIPT_PATH) || true; \
		# syntax check the installed script to catch generator errors early \
		if ! bash -n $(SCRIPT_PATH); then \
			echo "ERROR: syntax error in $(SCRIPT_PATH)"; exit 1; \
		fi; \
	else \
		echo "ERROR: ./scripts/$(SCRIPT_NAME) not found in repo. Please add it."; \
		exit 1; \
	fi

install-domains:
	@echo "Ensuring domains file exists..."
	@if [ ! -f $(DOMAINS_FILE) ]; then \
		install -m 644 /dev/null $(DOMAINS_FILE); \
		chown $(USER):$(GROUP) $(DOMAINS_FILE); \
		echo "Created empty domains file at $(DOMAINS_FILE). Edit it to add domains."; \
	fi

install-systemd:
	@echo "Installing systemd service and timer..."
	printf '%s\n' \
'[Unit]' \
'Description=DNS warm rotate job' \
'After=network.target' \
'' \
'[Service]' \
'Type=oneshot' \
'User=$(USER)' \
'Group=$(GROUP)' \
'ExecStart=/usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER)' \
'Nice=10' \
'Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
'' \
'[Install]' \
'WantedBy=multi-user.target' \
> $(SERVICE_PATH); \
	chmod 644 $(SERVICE_PATH); \
	printf '%s\n' \
'[Unit]' \
'Description=Run DNS warm rotate every minute' \
'' \
'[Timer]' \
'OnBootSec=1min' \
'OnUnitActiveSec=1min' \
'AccuracySec=1s' \
'' \
'[Install]' \
'WantedBy=timers.target' \
> $(TIMER_PATH); \
	chmod 644 $(TIMER_PATH); \
	systemctl daemon-reload

enable:
	@echo "Enabling and starting timer..."
	systemctl enable --now $(TIMER)

start:
	@echo "Starting service once..."
	systemctl start $(SERVICE)

stop:
	@echo "Stopping service/timer..."
	systemctl stop $(SERVICE) || true
	systemctl stop $(TIMER) || true

status:
	@echo "Timer status:"
	systemctl status $(TIMER) --no-pager || true
	@echo "Service status:"
	systemctl status $(SERVICE) --no-pager || true

test:
	@echo "Running one-off warm (test) as $(USER)..."
	@if [ "$$(id -u)" -eq 0 ]; then \
	  # We're root: run the script as the target user (use -- to stop sudo option parsing) \
	  sudo -u $(USER) -- /usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER); \
	else \
	  # Not root: run the script as the current user (no sudo) \
	  /usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER); \
	fi

disable:
	@echo "Disabling and stopping timer/service..."
	-@systemctl disable --now $(TIMER) 2>/dev/null || true
	-@systemctl stop $(SERVICE) 2>/dev/null || true
	-@systemctl stop $(TIMER) 2>/dev/null || true
	@echo "Disabled."

uninstall: disable
	@echo "Removing installed files and reloading systemd..."
	-@rm -f $(SERVICE_PATH) $(TIMER_PATH) $(SCRIPT_PATH) 2>/dev/null || true
	-@rm -f $(STATE_DIR)/state.csv 2>/dev/null || true
	-@rm -f $(DOMAINS_FILE) 2>/dev/null || true
	@systemctl daemon-reload
	@echo "Uninstalled."
#last line
