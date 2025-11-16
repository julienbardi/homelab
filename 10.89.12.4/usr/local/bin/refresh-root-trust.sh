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

log() {
  echo "$1"
  logger -t refresh-root-trust.sh "$1"
}

if [[ $EUID -ne 0 ]]; then
  log "❌ Error: must run as root (try: sudo $0)"
  exit 1
fi

ts=$(date -u +%Y%m%dT%H%M%SZ)
candidate="/var/lib/unbound/root.key.$ts"

llog "📥 Step 1: Fetching root-anchors.xml..."
if ! wget -q -O /var/lib/unbound/root-anchors.xml https://data.iana.org/root-anchors/root-anchors.xml; then
  log "❌ Failed to fetch root-anchors.xml"
  exit 1
fi

log "🔑 Step 2: Generating candidate trust anchor $candidate..."
output=$(unbound-anchor -a "$candidate" -f /var/lib/unbound/root-anchors.xml -v 2>&1)
echo "$output"

if grep -q "success" <<<"$output" && grep -q "DNSKEY" "$candidate"; then
  log "✅ Candidate $ts is valid, activating..."
  mv "$candidate" /var/lib/unbound/root.key
  chown unbound:unbound /var/lib/unbound/root.key
else
  log "❌ Candidate $ts invalid, marking with _ko"
  mv "$candidate" "${candidate}_ko"
fi

log "🕒 Step 3: Recording timestamp..."
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/unbound/rootkey.lastupdate
log "✅ Anchor refresh completed at $(cat /var/lib/unbound/rootkey.lastupdate)"

# Verify that it ran
#   cat /var/lib/unbound/rootkey.lastupdate
# Inspect the journal
#   sudo journalctl -u unbound -b | grep refresh-root-trust
