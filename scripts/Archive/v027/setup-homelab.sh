#!/usr/bin/env bash
#
# setup-homelab.sh — idempotent setup and status tool for homelab services
#
# Usage:
#   sudo bash setup-homelab.sh             # run full setup (services, cron, firewall, etc.) and show status
#   sudo bash setup-homelab.sh --status    # show human-readable status only
#   sudo bash setup-homelab.sh --status-json  # emit machine-readable JSON status only
#
# Notes:
# - Running without arguments will configure everything, ensure services/cron jobs are present,
#   trigger a backup, and then display the status dashboard.
# - Running with --status or --status-json will *only* perform that action and exit.

set -euo pipefail

VERSION_FILE="/var/lib/homelab-version"

increment_version() {
  if [[ -f "$VERSION_FILE" ]]; then
    CUR=$(cat "$VERSION_FILE")
  else
    CUR="v0.0"
  fi
  major=$(echo "$CUR" | cut -d. -f1 | tr -d v)
  minor=$(echo "$CUR" | cut -d. -f2)
  new_minor=$((minor + 1))
  NEW="v${major}.${new_minor}"
  echo "$NEW" > "$VERSION_FILE"
  echo "$NEW"
}

# Only bump version if running full setup (no args)
if [[ $# -eq 0 ]]; then
  VERSION=$(increment_version)
else
  VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "v0.0")
fi

LOG_TAG="[homelab $VERSION]"
AUDIT_LOG="/var/log/homelab-setup.log"

log() {
  local msg="$1"
  echo "$(date -Iseconds) $LOG_TAG $msg" | tee -a "$AUDIT_LOG" 2>/dev/null || echo "$(date -Iseconds) $LOG_TAG $msg"
}

# -----------------------------
# Hardened check functions
# -----------------------------
  check_service() {
    systemctl is-active "$1" >/dev/null 2>&1 && echo true || echo false
  }

  check_cron() {
    crontab -l 2>/dev/null | grep -q "$1" && echo true || echo false
  }

  check_file() {
    test -f "$1" && echo true || echo false
  }

  check_route() {
    if command -v tailscale >/dev/null 2>&1; then
      tailscale status --json 2>/dev/null | grep -q "192.168.50.0/24" && echo true || echo false
    else
      echo false
    fi
  }

  check_gro() {
    iface=$(ip route | awk '/default/ {print $5; exit}')
    if command -v ethtool >/dev/null 2>&1 && [[ -n "$iface" ]]; then
      ethtool -k "$iface" 2>/dev/null | grep -q 'generic-receive-offload: on' && echo true || echo false
    else
      echo false
    fi
  }

# -----------------------------
# Helpers
# -----------------------------
ensure_service() {
  local svc="$1"
  local unit_file="$2"
  local desired_content="$3"

  if [[ ! -f "$unit_file" ]] || ! cmp -s <(echo "$desired_content") "$unit_file"; then
    echo "$desired_content" > "$unit_file"
    systemctl daemon-reload
    systemctl stop "$svc" 2>/dev/null || true
    systemctl start "$svc"
    systemctl enable "$svc"
    log "updated and restarted $svc"
  else
    if ! systemctl is-active --quiet "$svc"; then
      systemctl start "$svc"
      log "started $svc"
    else
      log "$svc already running, no change"
    fi
  fi
}

ensure_cronjob() {
  local job="$1"
  ( crontab -l 2>/dev/null | grep -Fv "$job" ; echo "$job" ) | crontab -
  log "ensured cron job: $job"
}

ensure_logrotate() {
  local file="/etc/logrotate.d/headscale"
  if [[ ! -f "$file" ]]; then
    cat > "$file" <<'EOF'
/var/log/headscale/*.log {
  weekly
  rotate 4
  compress
  missingok
  notifempty
  copytruncate
}
EOF
    log "created logrotate config: $file"
  else
    log "logrotate config already present"
  fi
}

ensure_firewall() {
  iptables -C INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport 53 -j ACCEPT
  iptables -C INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 53 -j ACCEPT
  iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
  log "firewall rules ensured"
}
# -----------------------------
# Status JSON
# -----------------------------
show_status_json() {
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  LAST_BACKUP=$(ls -1t /var/lib/headscale/db.sqlite.*.bak 2>/dev/null | head -n1 || true)
  BACKUP_DATE=$(basename "$LAST_BACKUP" | cut -d. -f3 2>/dev/null || echo "missing")

  jq -n \
    --arg timestamp "$TIMESTAMP" \
    --arg dnsmasq "$(check_service dnsmasq)" \
    --arg headscale "$(check_service headscale)" \
    --arg subnet_router "$(check_service subnet-router.service)" \
    --arg tailscale_route "$(check_route)" \
    --arg gro "$(check_gro)" \
    --arg backup_cron "$(check_cron backup-headscale.sh)" \
    --arg healthcheck_cron "$(check_cron healthcheck-headscale.sh)" \
    --arg logrotate "$(check_file /etc/logrotate.d/headscale)" \
    --arg last_backup_date "${BACKUP_DATE:-missing}" \
    '{
      timestamp: $timestamp,
      dnsmasq_active: ($dnsmasq == "true"),
      headscale_active: ($headscale == "true"),
      subnet_router_active: ($subnet_router == "true"),
      tailscale_route_advertised: ($tailscale_route == "true"),
      gro_enabled: ($gro == "true"),
      last_backup_date: $last_backup_date,
      backup_cron_installed: ($backup_cron == "true"),
      healthcheck_cron_installed: ($healthcheck_cron == "true"),
      logrotate_config_present: ($logrotate == "true")
    }'
}

# -----------------------------
# Status Panel
# -----------------------------
show_status() {
  SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
  JSON="$("$SCRIPT_PATH" --status-json)"
  echo "$LOG_TAG status report at $(date -Iseconds)"
  echo "$JSON" | jq -r '
    to_entries | .[] |
    if .value == true then
      "🟢 " + .key + ": active"
    elif .value == false then
      "🔴 " + .key + ": inactive"
    else
      "🔴 " + .key + ": " + (.value|tostring)
    end
  '
}


# -----------------------------
# Unit file contents
# -----------------------------
DNSMASQ_UNIT_CONTENT="[Unit]
Description=DNS caching server
After=network.target

[Service]
ExecStart=/usr/sbin/dnsmasq -k
Restart=always

[Install]
WantedBy=multi-user.target
"

HEADSCALE_UNIT_CONTENT="[Unit]
Description=Headscale coordination server
After=network.target

[Service]
ExecStart=/usr/local/bin/headscale serve
Restart=always

[Install]
WantedBy=multi-user.target
"

SUBNET_ROUTER_UNIT_CONTENT="[Unit]
Description=Tailscale Subnet Router
After=network.target

[Service]
ExecStart=/usr/local/bin/setup-subnet-router.sh
Restart=always

[Install]
WantedBy=multi-user.target
"

# -----------------------------
# Argument handling
# -----------------------------
case "${1:-}" in
  --status)
    show_status
    exit 0
    ;;
  --status-json)
    show_status_json
    exit 0
    ;;
esac

# -----------------------------
# Default: full setup
# -----------------------------
log "running full homelab setup"

ensure_service "dnsmasq" "/etc/systemd/system/dnsmasq.service" "$DNSMASQ_UNIT_CONTENT"
ensure_service "headscale" "/etc/systemd/system/headscale.service" "$HEADSCALE_UNIT_CONTENT"
ensure_service "subnet-router.service" "/etc/systemd/system/subnet-router.service" "$SUBNET_ROUTER_UNIT_CONTENT"

ensure_cronjob "0 3 * * * /usr/local/bin/backup-headscale.sh"
ensure_cronjob "*/5 * * * * /usr/local/bin/healthcheck-headscale.sh"

ensure_logrotate
ensure_firewall

# Trigger a backup immediately so status shows a recent backup
if [[ -x /usr/local/bin/backup-headscale.sh ]]; then
  /usr/local/bin/backup-headscale.sh && log "backup triggered"
fi

# Show status at the end
show_status

echo "$(date -Iseconds) $LOG_TAG completed setup run"
