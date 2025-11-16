#!/bin/bash
# dns-health-check.sh
# Purpose: Verify local DNS recursion and DNSSEC validation with clear, plain-English output.
#
# To deploy use:
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/dns-health-check.sh /usr/local/bin/; sudo chmod 755 /usr/local/bin/dns-health-check.sh
#   # Optional: wire into Unbound as an ExecStartPost health probe (non-blocking)
#   #   sudo systemctl edit unbound
#   #   [Service]
#   #   ExecStartPost=/usr/local/bin/dns-health-check.sh 127.0.0.1 || true
#   #   sudo systemctl daemon-reload; sudo systemctl restart unbound
#   # Optional: run via cron for regular checks
#   #   echo '*/30 * * * * root /usr/local/bin/dns-health-check.sh 127.0.0.1' | sudo tee /etc/cron.d/dns-health-check
#
# Usage: sudo /usr/local/bin/dns-health-check.sh [resolver_ip]
# Default resolver_ip: 127.0.0.1

set -euo pipefail

# must run as root for consistent environment and syslog
if [[ $EUID -ne 0 ]]; then
  echo "❌ Must be run with sudo (root) for reliable logging and consistent environment. Try: sudo $0"
  exit 1
fi

RESOLVER="${1:-127.0.0.1}"
TIMEOUT_SECONDS=5

log() {
  echo "$1"
  logger -t dns-health-check.sh "$1" || true
}

# required commands
for cmd in dig sed grep logger awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd"; exit 2; }
done

# --- in‑memory dig runner and robust extractors (single copy) ---
export LC_ALL=C LANG=C

dig_q() {
  # return full dig output as stdout (caller captures into a variable)
  dig @"$RESOLVER" "$@" +tries=1 +time="$TIMEOUT_SECONDS" 2>/dev/null || true
}

# run_query returns the raw dig output (or the sentinel "%%EMPTY%%")
run_query() {
  local out
  out="$(dig_q "$@")"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    printf '%%EMPTY%%'
  else
    printf '%s' "$out"
  fi
}

get_header() {
  # $1 = raw dig output
  local raw line
  raw="$1"
  while IFS= read -r line; do
    case "$line" in
      ';; ->>HEADER<<-'* ) printf '%s\n' "${line#;; ->>HEADER<<- }"; return ;;
      *';; ->>HEADER<<-'* ) printf '%s\n' "${line#*;; ->>HEADER<<- }"; return ;;
    esac
  done <<<"$raw"
}

get_status() {
  # $1 = raw dig output or sentinel; return NOERROR|SERVFAIL|NXDOMAIN etc.
  local raw line tok s
  raw="$1"
  if [[ "$raw" == "%%EMPTY%%" ]]; then return; fi
  while IFS= read -r line; do
    # scan tokens on each line for "status:"
    for tok in $line; do
      case "$tok" in
        status:*) s="${tok#status:}"; s="${s//[^A-Z]/}"; [[ -n "$s" ]] && printf '%s\n' "$s" && return ;;
      esac
    done
    # also handle if "status:" appears in the middle (e.g. punctuation attached)
    if [[ "$line" == *"status:"* ]]; then
      s="${line#*status:}"
      # keep only letters A-Z from the start
      s="${s%%[^A-Z]*}"
      if [[ -n "$s" ]]; then printf '%s\n' "$s"; return; fi
    fi
  done <<<"$raw"
}

get_flags() {
  # $1 = raw dig output or sentinel; return e.g. "qr rd ra ad"
  local raw line rest
  raw="$1"
  if [[ "$raw" == "%%EMPTY%%" ]]; then return; fi
  while IFS= read -r line; do
    case "$line" in
      ';; flags:'* )
        rest="${line#;; flags: }"
        rest="${rest%%;*}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        printf '%s\n' "$rest"
        return
        ;;
      *';; flags:'* )
        rest="${line#*;; flags: }"
        rest="${rest%%;*}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        rest="${rest%"${rest##*[![:space:]]}"}"
        printf '%s\n' "$rest"
        return
        ;;
    esac
  done <<<"$raw"
}
# --- end in-memory runner+extractors ---

# run a dig and return raw output; ensure non-empty
run_query() {
  local out
  out="$(dig_q "$@")"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    # empty output -> return a marker so callers can handle gracefully
    printf '%%EMPTY%%'
  else
    printf '%s' "$out"
  fi
}

# 1) Recursion check (use a stable public name)
rec_raw="$(run_query www.example.com A)"
rec_hdr="$(get_header "$rec_raw" || true)"
rec_status="$(get_status "$rec_raw" || true)"
rec_flags="$(get_flags "$rec_raw" || true)"
rec_has_ra=false
if [[ "$rec_flags" != "%%EMPTY%%" ]] && printf " %s " "$rec_flags" | grep -q ' ra '; then
  rec_has_ra=true
fi
rec_ok=false
if [[ "${rec_status:-}" == "NOERROR" && "$rec_has_ra" == "true" ]]; then
  rec_ok=true
fi

# 2) DNSSEC positive (sigok)
pos_raw="$(run_query sigok.verteiltesysteme.net A +dnssec)"
pos_status="$(get_status "$pos_raw" || true)"
pos_flags="$(get_flags "$pos_raw" || true)"
pos_has_ad=false
if [[ "$pos_flags" != "%%EMPTY%%" ]] && printf " %s " "$pos_flags" | grep -q ' ad '; then
  pos_has_ad=true
fi
pos_ok=false
if [[ "${pos_status:-}" == "NOERROR" && "$pos_has_ad" == "true" ]]; then
  pos_ok=true
fi

# 3) DNSSEC negative (sigfail)
neg_raw="$(run_query sigfail.verteiltesysteme.net A +dnssec)"
neg_status="$(get_status "$neg_raw" || true)"
neg_ok=false
if [[ "${neg_status:-}" == "SERVFAIL" ]]; then
  neg_ok=true
fi

# Output summary
log "🧪 DNS health check against resolver ${RESOLVER}"
log "• Recursion: $([[ "$rec_ok" == "true" ]] && echo PASS || echo FAIL) (status=${rec_status:-n/a}, flags=${rec_flags:-n/a})"
log "• DNSSEC positive (sigok): $([[ "$pos_ok" == "true" ]] && echo PASS || echo FAIL) (status=${pos_status:-n/a}, flags=${pos_flags:-n/a})"
log "• DNSSEC negative (sigfail): $([[ "$neg_ok" == "true" ]] && echo PASS || echo FAIL) (status=${neg_status:-n/a})"

# Verdict and guidance
if [[ "$rec_ok" == "true" && "$pos_ok" == "true" && "$neg_ok" == "true" ]]; then
  log "✅ DNS resolver is performing recursion and validating DNSSEC correctly."
  exit 0
fi

if [[ "$rec_ok" != "true" ]]; then
  log "❌ Recursion failed — check access-control, forward-zone config, and upstream reachability. Manual dig: dig @$RESOLVER www.example.com A"
fi
if [[ "$pos_ok" != "true" ]]; then
  log "❌ DNSSEC positive test failed — missing AD on sigok; check unbound val-enable, upstreams, and system clock (NTP). Manual dig: dig @$RESOLVER sigok.verteiltesysteme.net A +dnssec"
fi
if [[ "$neg_ok" != "true" ]]; then
  log "❌ DNSSEC negative test failed — sigfail should SERVFAIL; if it returns NOERROR validation may be bypassed. Manual dig: dig @$RESOLVER sigfail.verteiltesysteme.net A +dnssec"
fi

exit 1
