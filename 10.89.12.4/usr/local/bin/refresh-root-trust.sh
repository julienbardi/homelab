#!/bin/bash
# refresh-root-trust.sh
# purpose: refresh unbound root trust anchor and record timestamp
# to deploy use
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/refresh-root-trust.sh /usr/local/bin/;sudo chmod 755 /usr/local/bin/refresh-root-trust.sh
#   wire it into systemd; sudo systemctl edit unbound
#   enter
#   [Service]
#   ExecStartPre=/usr/local/bin/refresh-root-trust.sh
#   then reload and restart unbound
#   sudo systemctl daemon-reload;sudo systemctl restart unbound
#   verify that both show today's timestamp:
#   ls -l /var/lib/unbound/root.hints
#   cat /var/lib/unbound/rootkey.lastupdate
#

#!/bin/bash
# refresh-root-trust.sh
# purpose: refresh unbound root trust anchor and root hints, record timestamp
set -euo pipefail

# Enable bash tracing if DEBUG=1 is exported
[[ "${DEBUG:-0}" == "1" ]] && set -x

log() {
  echo "$1"
  logger -t refresh-root-trust.sh "$1" || echo "⚠️logger failed: $1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "❌ Missing command: $1"; exit 1; }
}

require_cmd wget
require_cmd unbound-anchor

if [[ $EUID -ne 0 ]]; then
  log "❌ Error: must run as root (try: sudo $0)"
  exit 1
fi

ts=$(date -u +%Y%m%dT%H%M%SZ)
candidate="/var/lib/unbound/root.key.$ts"
anchors_xml="/var/lib/unbound/root-anchors.xml"
hints="/var/lib/unbound/root.hints"

log "🌐 Step 1: Refreshing root hints..."
if wget -q -O "$hints" https://www.internic.net/domain/named.root; then
  log "✅ Root hints updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
else
  log "❌ Failed to update root hints"
  exit 1
fi

log "📥 Step 2: Fetching root-anchors.xml..."
if wget -q -O "$anchors_xml" https://data.iana.org/root-anchors/root-anchors.xml; then
  log "✅ root-anchors.xml downloaded"
else
  log "❌ Failed to fetch root-anchors.xml"
  exit 1
fi

log "🔑 Step 3: Generating trust anchor..."
ua_out=$(unbound-anchor -a "$root_key.$ts" -f "$anchors_xml" 2>&1 || true)
#echo "$ua_out"
if [ -s "$root_key.$ts" ] && grep -q "DNSKEY" "$root_key.$ts"; then
  cp -p "$root_key.$ts" "$root_key"
  chown unbound:unbound "$root_key"
  chmod 644 "$root_key"
  log "✅ Trust anchor refreshed"
else
  log "❌ unbound-anchor failed; keeping existing root.key"
fi

log "🕒 Step 4: Recording timestamp..."
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/unbound/rootkey.lastupdate
log "✅ Completed at $(cat /var/lib/unbound/rootkey.lastupdate)"

# rotate backups using standalone rotator (no-op if not present)
if command -v /usr/local/bin/rotate-unbound-rootkeys.sh >/dev/null 2>&1; then
  if (( EUID == 0 )); then
    /usr/local/bin/rotate-unbound-rootkeys.sh
    rc=$?
  else
    # use -n so sudo does not block waiting for a password (returns 1 instead)
    sudo -n /usr/local/bin/rotate-unbound-rootkeys.sh
    rc=$?
  fi

  if (( rc != 0 )); then
    log "⚠️ rotate-unbound-rootkeys.sh failed (exit=${rc})"
  fi
fi

# Verify that it ran
#   cat /var/lib/unbound/rootkey.lastupdate
# Inspect the journal
#   sudo journalctl -u unbound -b | grep refresh-root-trust
