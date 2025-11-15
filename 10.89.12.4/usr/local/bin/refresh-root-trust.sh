#!/bin/bash
# refresh-root-trust.sh
# purpose: refresh unbound root trust anchor and record timestamp
# to deploy use 
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/refresh-root-trust.sh /usr/local/bin/;sudo chmod 755 /usr/local/bin/refresh-root-trust.sh
set -euo pipefail

# --- safety check: must run as root ---
if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

# --- refresh trust anchor ---
unbound-anchor -a /var/lib/unbound/root.key -r /var/lib/unbound/root.hints

# --- record timestamp ---
date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/unbound/rootkey.lastupdate