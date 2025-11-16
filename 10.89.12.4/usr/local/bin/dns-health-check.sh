#!/bin/bash
# dns-health-check.sh
# Purpose: Verify local DNS recursion and DNSSEC validation with clear, plain-English output.
#
# To deploy use:
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/dns-health-check.sh /usr/local/bin/;sudo chmod 755 /usr/local/bin/dns-health-check.sh
#   # Optional: wire into Unbound as an ExecStartPost health probe (non-blocking)
#   #   sudo systemctl edit unbound
#   #   [Service]
#   #   ExecStartPost=/usr/local/bin/dns-health-check.sh 127.0.0.1 || true
#   #   sudo systemctl daemon-reload; sudo systemctl restart unbound
#   # Optional: run via cron for regular checks
#   #   echo '*/30 * * * * root /usr/local/bin/dns-health-check.sh 127.0.0.1' | sudo tee /etc/cron.d/dns-health-check
#
# Usage: sudo ./dns-health-check.sh [resolver_ip]
# Default resolver_ip: 127.0.0.1


set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ Must be run with sudo (root) for reliable logging and consistent environment. Try: sudo $0"
  exit 1
fi

RESOLVER="${1:-127.0.0.1}"

log() {
  echo "$1"
  logger -t dns-health-check.sh "$1" || true
}

for cmd in dig sed grep; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd"; exit 2; }
done

# Extract header line and parts safely
get_header() { echo "$1" | sed -n 's/^;; ->>HEADER<<- \(.*\)$/\1/p'; }
get_status() { echo "$1" | sed -n 's/^;; ->>HEADER<<- .*status: \([A-Z]\+\).*/\1/p'; }
get_flags()  { echo "$1" | sed -n 's/^;; ->>HEADER<<- .*flags: \([^;]*\).*/\1/p'; }

dig_q() {
  dig @"$RESOLVER" "$@" +tries=1 +time=2 2>/dev/null
}

# 1) Recursion check
rec_out="$(dig_q www.example.com A)"
rec_hdr="$(get_header "$rec_out")"
rec_status="$(get_status "$rec_out")"
rec_flags="$(get_flags "$rec_out")"
rec_has_ra=false
if [[ -n "${rec_flags:-}" ]] && echo " $rec_flags " | grep -q ' ra '; then
  rec_has_ra=true
fi
rec_ok=false
if [[ "${rec_status:-}" == "NOERROR" && "$rec_has_ra" == "true" ]]; then
  rec_ok=true
fi

# 2) DNSSEC positive (sigok)
pos_out="$(dig_q sigok.verteiltesysteme.net A +dnssec)"
pos_hdr="$(get_header "$pos_out")"
pos_status="$(get_status "$pos_out")"
pos_has_ad=false
if [[ -n "${pos_hdr:-}" ]] && echo " $pos_hdr " | grep -q ' ad '; then
  pos_has_ad=true
fi
pos_ok=false
if [[ "${pos_status:-}" == "NOERROR" && "$pos_has_ad" == "true" ]]; then
  pos_ok=true
fi

# 3) DNSSEC negative (sigfail)
neg_out="$(dig_q sigfail.verteiltesysteme.net A +dnssec)"
neg_status="$(get_status "$neg_out")"
neg_ok=false
if [[ "${neg_status:-}" == "SERVFAIL" ]]; then
  neg_ok=true
fi

log "🧪 DNS health check against resolver ${RESOLVER}"
log "• Recursion: $([[ "$rec_ok" == "true" ]] && echo PASS || echo FAIL) (status=${rec_status:-n/a}, flags=${rec_flags:-n/a})"
log "• DNSSEC positive (sigok): $([[ "$pos_ok" == "true" ]] && echo PASS || echo FAIL) (status=${pos_status:-n/a})"
log "• DNSSEC negative (sigfail): $([[ "$neg_ok" == "true" ]] && echo PASS || echo FAIL) (status=${neg_status:-n/a})"

if [[ "$rec_ok" == "true" && "$pos_ok" == "true" && "$neg_ok" == "true" ]]; then
  log "✅ DNS resolver is performing recursion and validating DNSSEC correctly."
  exit 0
fi

if [[ "$rec_ok" != "true" ]]; then
  log "❌ Recursion failed — check access controls, forward-zone config, and upstream reachability."
fi
if [[ "$pos_ok" != "true" ]]; then
  log "❌ DNSSEC positive test failed — missing AD on sigok; ensure val-enable yes, correct clock (NTP), and no non-validating forwarders."
fi
if [[ "$neg_ok" != "true" ]]; then
  log "❌ DNSSEC negative test failed — sigfail should SERVFAIL; if it returns NOERROR, validation may be bypassed or disabled."
fi

exit 1