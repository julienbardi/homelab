# 71_dns-warm.mk - self-contained installer for DNS warm rotate (no heredocs)
# Usage:
#   sudo make -f mk/71_dns-warm.mk install USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk enable USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk disable USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk uninstall USER=dnswarm
#   sudo make -f mk/71_dns-warm.mk test USER=dnswarm

PREFIX ?= /usr/local
BIN_DIR ?= $(PREFIX)/bin
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
	@if ! id -u $(USER) >/dev/null 2>&1; then \
		useradd --system --no-create-home --shell /usr/sbin/nologin --user-group $(USER) || true; \
	fi
	@if ! getent group $(GROUP) >/dev/null 2>&1; then \
		groupadd --system $(GROUP) || true; \
		usermod -g $(GROUP) $(USER) || true; \
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
	@if [ -f ./dns-warm-rotate.sh ]; then \
		install -m 755 -D ./dns-warm-rotate.sh $(SCRIPT_PATH); \
	else \
		printf '%s\n' \
'#!/usr/bin/env bash' \
'set -euo pipefail' \
'IFS=$'\''\n\t'\''' \
'' \
'RESOLVER="${1:-127.0.0.1}"' \
'DOMAINS_FILE="/etc/dns-warm/domains.txt"' \
'STATE_FILE="/var/lib/dns-warm/state.csv"' \
'WORKERS=10' \
'PER_RUN=100' \
'DIG_TIMEOUT=2' \
'DIG_TRIES=1' \
'LOCKFILE="/var/lock/dns-warm-rotate.lock"' \
'' \
'mkdir -p "$(dirname "$STATE_FILE")"' \
'' \
'log() { printf "%s %s\n" "$(date +%Y-%m-%d\ %H:%M:%S)" "$*"; }' \
'' \
'# Create default domains file if missing' \
'if [ ! -f "$DOMAINS_FILE" ]; then' \
'  printf '\''%s\n'\'' '\''srf.ch'\'' '\''20min.ch'\'' '\''blick.ch'\'' '\''galaxus.ch'\'' '\''ricardo.ch'\'' '\''admin.ch'\'' '\''sbb.ch'\'' '\''migros.ch'\'' '\''tagesanzeiger.ch'\'' '\''watson.ch'\'' '\''digitec.ch'\'' '\''post.ch'\'' '\''rts.ch'\'' '\''google.ch'\'' '\''google.com'\'' '\''youtube.com'\'' '\''amazon.de'\'' '\''netflix.com'\'' '\''github.com'\'' '\''linkedin.com'\'' '\''spotify.com'\'' '\''wikipedia.org'\'' > "$DOMAINS_FILE"' \
'  chmod 644 "$DOMAINS_FILE"' \
'fi' \
'' \
'# Initialize state file if missing or add new domains' \
'init_state() {' \
'  if [ ! -f "$STATE_FILE" ]; then' \
'    awk '\''{print $$0",0"}'\'' "$DOMAINS_FILE" > "$STATE_FILE"' \
'    chmod 640 "$STATE_FILE"' \
'    return' \
'  fi' \
'' \
'  while read -r d; do' \
'    [ -z "$d" ] && continue' \
'    if ! awk -F, -v dom="$d" '\''$$1==dom{exit 0} END{exit 1}'\'' "$STATE_FILE"; then' \
'      echo "$d,0" >> "$STATE_FILE"' \
'    fi' \
'  done < "$DOMAINS_FILE"' \
'}' \
'' \
'# Select oldest PER_RUN domains (writes to stdout)' \
'select_oldest() {' \
'  awk -F, '\''{print $$2","$$1}'\'' "$STATE_FILE" | sort -n | awk -F, -v n="$PER_RUN" '\''NR<=n{print $$2}'\'' ' \
'}' \
'' \
'# Update state for warmed domains (set last_epoch to now)' \
'update_state() {' \
'  local now tmp' \
'  now="$(date +%s)"' \
'  tmp="$(mktemp)"' \
'  while IFS=, read -r dom last; do' \
'    if echo "$1" | grep -qw "$dom"; then' \
'      echo "$dom,$now"' \
'    else' \
'      echo "$dom,$last"' \
'    fi' \
'  done < "$STATE_FILE" > "$tmp"' \
'  mv "$tmp" "$STATE_FILE"' \
'}' \
'' \
'# Warm a single domain (A, AAAA, NS)' \
'warm_domain() {' \
'  local d="$1"' \
'  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" A >/dev/null 2>&1 || true' \
'  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" AAAA >/dev/null 2>&1 || true' \
'  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" NS >/dev/null 2>&1 || true' \
'}' \
'' \
'main() {' \
'  exec 9>"$LOCKFILE"' \
'  if ! flock -n 9; then' \
'    log "Another instance is running; exiting"' \
'    exit 0' \
'  fi' \
'' \
'  init_state' \
'' \
'  # Use a temp file instead of process substitution for portability' \
'  tmpfile="$(mktemp)"' \
'  select_oldest > "$tmpfile"' \
'  mapfile -t to_warm < "$tmpfile"' \
'  rm -f "$tmpfile"' \
'' \
'  if [ "${#to_warm[@]}" -eq 0 ]; then' \
'    log "No domains to warm"' \
'    exit 0' \
'  fi' \
'' \
'  log "Warming ${#to_warm[@]} domains (resolver=${RESOLVER})"' \
'' \
'  sem=0' \
'  warmed_list=""' \
'  for d in "${to_warm[@]}"; do' \
'    warm_domain "$d" &' \
'    ((sem++))' \
'    warmed_list="$warmed_list $d"' \
'    if [ "$sem" -ge "$WORKERS" ]; then' \
'      wait -n || true' \
'      sem=$((sem-1))' \
'    fi' \
'  done' \
'' \
'  wait || true' \
'' \
'  update_state "$warmed_list"' \
'  log "Warming complete; updated state for ${#to_warm[@]} domains"' \
'}' \
'' \
'main || true' \
> $(SCRIPT_PATH); \
		chmod 755 $(SCRIPT_PATH); \
	fi; \
	chown $(USER):$(GROUP) $(SCRIPT_PATH) || true

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
	sudo -u $(USER) /usr/bin/env bash $(SCRIPT_PATH) $(RESOLVER)

disable:
	@echo "Disabling and stopping timer/service..."
	-@systemctl disable --now $(TIMER) 2>/dev/null || true
	-@systemctl stop $(SERVICE) 2>/dev/null || true
	-@systemctl stop $(TIMER) 2>/dev/null || true
	@echo "Disabled."

uninstall: disable
	@echo "Removing installed files and reloading systemd..."
	-@rm -f $(SERVICE_PATH) $(TIMER_PATH) $(SCRIPT_PATH) 2>/dev/null || true
	-@rm -rf $(STATE_DIR) $(DOMAINS_DIR) 2>/dev/null || true
	@systemctl daemon-reload
	@echo "Uninstalled."
#last line
