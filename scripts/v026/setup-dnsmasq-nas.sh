#!/usr/bin/env bash
#
# setup-dnsmasq-nas.sh — IPv4‑only DNS for NAS
# Ensures dnsmasq listens only on IPv4 + loopback, with managed hosts file.
set -euo pipefail

SCRIPT_VERSION="v1.9"
CONFIG_SNIPPET="/etc/dnsmasq.d/10-nas-dns.conf"
HOSTS_FILE="/etc/dnsmasq.hosts"
OVERRIDE_DIR="/etc/systemd/system/dnsmasq.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/override.conf"
STATIC_IPV4="192.168.50.4"

log() { echo -e "$*"; }

# === [1] PRECHECKS ===
log "🔐 [1] Checking prerequisites"
for bin in sudo tee systemctl cmp ip; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "❌ Missing required tool: $bin"
    exit 1
  fi
done
log "✅ All required tools present"

# === [2] BUILD EXPECTED CONFIG (IPv4 only) ===
EXPECTED_CONTENT="# dnsmasq binding for NAS resolver (IPv4 only)
bind-interfaces
listen-address=127.0.0.1,$STATIC_IPV4
domain=bardi.ch
expand-hosts
local=/bardi.ch/
addn-hosts=$HOSTS_FILE"

# === [3] COMPARE AND APPLY CONFIG ===
if [[ ! -f "$CONFIG_SNIPPET" ]] || ! cmp -s <(echo "$EXPECTED_CONTENT") "$CONFIG_SNIPPET"; then
  log "📝 Updating $CONFIG_SNIPPET"
  echo "$EXPECTED_CONTENT" | sudo tee "$CONFIG_SNIPPET" >/dev/null
else
  log "✅ Config already up to date"
fi

# === [4] MANAGE HOSTS FILE ===
log "📒 [4] Ensuring homelab hostnames in $HOSTS_FILE"
HOSTS_CONTENT="192.168.50.1 router.bardi.ch router
192.168.50.2 diskstation.bardi.ch diskstation
192.168.50.3 qnap.bardi.ch qnap
192.168.50.4 nas.bardi.ch nas"

if [[ ! -f "$HOSTS_FILE" ]] || ! cmp -s <(echo "$HOSTS_CONTENT") "$HOSTS_FILE"; then
  echo "$HOSTS_CONTENT" | sudo tee "$HOSTS_FILE" >/dev/null
  log "📝 Hosts file written to $HOSTS_FILE"
else
  log "✅ Hosts file already up to date"
fi

# === [5] ENSURE SYSTEMD OVERRIDE ===
log "⚙️ [5] Ensuring systemd override for dnsmasq"
sudo mkdir -p "$OVERRIDE_DIR"
OVERRIDE_CONTENT="[Service]
ExecStart=
ExecStart=/usr/sbin/dnsmasq -k --conf-dir=/etc/dnsmasq.d
Type=simple
ExecStartPre=
ExecStartPost=
ExecStop=
"
if [[ ! -f "$OVERRIDE_FILE" ]] || ! cmp -s <(echo "$OVERRIDE_CONTENT") "$OVERRIDE_FILE"; then
  echo "$OVERRIDE_CONTENT" | sudo tee "$OVERRIDE_FILE" >/dev/null
  log "📝 Override written to $OVERRIDE_FILE"
else
  log "✅ Override already up to date"
fi

# === [6] CLEAN UP STRAY PROCESSES ===
log "🧹 Killing any stray dnsmasq processes"
sudo pkill -9 dnsmasq || true

# === [7] RELOAD AND RESTART ===
log "🔄 Reloading systemd and restarting dnsmasq"
sudo systemctl daemon-reexec
sudo systemctl restart dnsmasq
log "✅ dnsmasq restarted with override"

# === [8] VERIFY LISTENERS ===
log "🔍 Verifying port 53 bindings"
sudo ss -tuln | grep :53 || log "⚠️ No listeners found!"

# === [9] FOOTER ===
TIMESTAMP="$(date +'%F %T')"
BOOT_LOG="setup-dnsmasq-nas.sh $SCRIPT_VERSION @ $TIMESTAMP"
log "🏁 Setup complete — $BOOT_LOG"

# Write a one‑liner to syslog so it appears at boot
logger -t setup-dnsmasq-nas "$BOOT_LOG"

log "ℹ️ Reminder: On Windows clients, run once to pin DNS:"
log "    Set-DnsClientServerAddress -InterfaceAlias \"Ethernet 3\" -ServerAddresses (\"$STATIC_IPV4\")"
