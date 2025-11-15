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
  # Log both to stdout and systemd journal
  echo "$1"
  logger -t refresh-root-trust.sh "$1"
}

# --- safety check: must run as root ---
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

log "🌐 Step 1: Refreshing root hints..."
if wget -q -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root; then
  log "✅ Root hints updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
else
  log "❌ Failed to update root hints"
  exit 1
fi

log "🔑 Step 2: Attempting trust anchor refresh..."
if unbound-anchor -a /var/lib/unbound/root.key -r /var/lib/unbound/root.hints -v; then
  log "✅ Trust anchor refreshed successfully."
else
  log "❌ Anchor invalid, forcing bootstrap..."
  rm -f /var/lib/unbound/root.key
  if wget -q -O /var/lib/unbound/root-anchors.xml https://data.iana.org/root-anchors/root-anchors.xml; then
    if unbound-anchor -a /var/lib/unbound/root.key -f /var/lib/unbound/root-anchors.xml -v; then
      log "✅ Trust anchor bootstrapped from root-anchors.xml."
    else
      log "❌ Failed to bootstrap trust anchor"
      exit 1
    fi
  else
    log "❌ Could not fetch root-anchors.xml"
    exit 1
  fi
fi

log "🔧 Step 3: Fixing file ownership..."
chown unbound:unbound /var/lib/unbound/root.key /var/lib/unbound/root.hints || true
log "✅ Ownership set to unbound:unbound"

log "🕒 Step 4: Recording timestamp..."
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/unbound/rootkey.lastupdate
log "✅ Anchor refresh completed at $(cat /var/lib/unbound/rootkey.lastupdate)"

# Verify that it ran
#   cat /var/lib/unbound/rootkey.lastupdate
# Inspect the journal
#   sudo journalctl -u unbound -b | grep refresh-root-trust
