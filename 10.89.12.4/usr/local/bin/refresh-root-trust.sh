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

# --- safety check: must run as root ---
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

echo "🌐 Step 1: Refreshing root hints..."
wget -q -O /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
echo "✅ Root hints updated at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "🔑 Step 2: Attempting trust anchor refresh..."
if unbound-anchor -a /var/lib/unbound/root.key -r /var/lib/unbound/root.hints -v; then
    echo "✅ Trust anchor refreshed successfully."
else
    echo "❌ Anchor invalid, forcing bootstrap..."
    rm -f /var/lib/unbound/root.key

    # Try direct XML fetch from IANA
    wget -q -O /var/lib/unbound/root-anchors.xml https://data.iana.org/root-anchors/root-anchors.xml
    if unbound-anchor -a /var/lib/unbound/root.key -f /var/lib/unbound/root-anchors.xml -v; then
        echo "✅ Trust anchor bootstrapped from root-anchors.xml."
    else
        echo "❌ Failed to bootstrap trust anchor. Check connectivity or XML file."
        exit 1
    fi
fi

echo "🔧 Step 3: Fixing file ownership..."
chown unbound:unbound /var/lib/unbound/root.key /var/lib/unbound/root.hints || true
echo "✅ Ownership set to unbound:unbound"

echo "🕒 Step 4: Recording timestamp..."
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/unbound/rootkey.lastupdate
echo "✅ Anchor refresh completed at $(cat /var/lib/unbound/rootkey.lastupdate)"

# Verify that it ran
#   cat /var/lib/unbound/rootkey.lastupdate
# Inspect the journal
#   sudo journalctl -u unbound -b | grep refresh-root-trust
