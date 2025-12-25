#!/usr/bin/env bash
# dns-health-check.sh
#
# Purpose:
#   Verify DNS recursion and DNSSEC enforcement with clear, plain-English output.
#
# Design notes (layered DNS):
# - DNSSEC validation is enforced upstream (e.g., Unbound).
# - At the client edge (e.g., via dnsdist / DoH), the AD bit may be absent by design.
# - DNSSEC enforcement is proven by failure on known-bad signatures.
#
# Assertions:
#   1) Recursion works (NOERROR + RA)
#   2) DNSSEC-positive name resolves (NOERROR)
#   3) DNSSEC-negative name fails validation (SERVFAIL)
#   4) Optional: DoH DNSSEC enforcement (SERVFAIL or HTTP-level failure)
#
# Usage:
#   Classic DNS (UDP/TCP) checks against a resolver IP:
#     sudo ./scripts/dns-health-check.sh [resolver_ip]
#
#   Optional DoH DNSSEC check (in addition to classic DNS checks):
#     sudo DOH_HOST=dns.example.com DOH_PATH=/dns-query ./scripts/dns-health-check.sh
#
# Notes:
#   - [resolver_ip] applies only to classic DNS tests (sections 1–3).
#   - DoH tests (section 4) always use DOH_HOST / DOH_PATH and ignore resolver_ip.
#
# Default resolver_ip: 127.0.0.1

set -euo pipefail

# Must run as root for consistent environment and syslog
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "❌ Must be run with sudo (root) for reliable logging and consistent environment. Try: sudo $0"
  exit 1
fi

RESOLVER="${1:-127.0.0.1}"
TIMEOUT_SECONDS=5
MAX_RETRIES=3

# Optional DoH configuration
DOH_HOST="${DOH_HOST:-}"
DOH_PATH="${DOH_PATH:-}"

log() {
  local msg="$1"
  echo "$msg"
  logger -t dns-health-check.sh "$msg" || true
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      echo "Missing required command: $c"
      exit 2
    }
  done
}

require_cmd dig sed grep logger awk head tr date stat expr
if [[ -n "$DOH_HOST" ]]; then
  require_cmd kdig
fi

export LC_ALL=C LANG=C

dig_q() {
  dig @"$RESOLVER" "$@" +tries=1 +time="$TIMEOUT_SECONDS" 2>&1 || true
}

run_query() {
  local out tries=0
  while :; do
    out="$(dig_q "$@")"
    if [[ -n "${out//[[:space:]]/}" ]] && ! printf '%s' "$out" | grep -qEi 'communications error'; then
      printf '%s' "$out"
      return 0
    fi
    tries=$((tries+1))
    if [[ $tries -ge $MAX_RETRIES ]]; then
      printf '%s' "$out"
      return 0
    fi
    sleep 1
  done
}

get_status() {
  local raw header s
  raw="${1:-$(cat)}"
  [[ -z "${raw:-}" ]] && return 0

  header="$(printf '%s' "$raw" | sed -n '/->>HEADER<<-/p' | head -n1 || true)"
  if [[ -n "$header" ]]; then
    s="$(printf '%s' "$header" | grep -oEi 'status:[[:space:]]*[A-Za-z]+' | head -n1 || true)"
    if [[ -n "$s" ]]; then
      printf '%s' "${s#*:}" | tr '[:lower:]' '[:upper:]' | sed 's/^ *//;s/ *$//'
      return 0
    fi
  fi

  s="$(printf '%s' "$raw" | grep -oEi 'SERVFAIL|NOERROR|NXDOMAIN' | head -n1 || true)"
  [[ -n "$s" ]] && printf '%s' "$s" | tr '[:lower:]' '[:upper:]'
}

get_flags() {
  local raw line rest
  raw="${1:-$(cat)}"
  [[ -z "$raw" ]] && return 0

  while IFS= read -r line; do
    case "$line" in
      *';; flags:'* )
        rest="${line#*;; flags: }"
        rest="${rest%%;*}"
        printf '%s\n' "$rest"
        return 0
        ;;
    esac
  done <<<"$raw"
}

flags_has() {
  local flags="$1"
  local tok="$2"
  printf ' %s ' "$flags" | grep -q " ${tok} "
}

# ------------------------------------------------------------
# 1) Recursion
# ------------------------------------------------------------
rec_raw="$(run_query www.example.com A)"
rec_status="$(get_status "$rec_raw")"
rec_flags="$(get_flags "$rec_raw")"

rec_ok=false
if [[ "$rec_status" == "NOERROR" ]] && flags_has "$rec_flags" "ra"; then
  rec_ok=true
fi

# ------------------------------------------------------------
# 2) DNSSEC positive
# ------------------------------------------------------------
pos_raw="$(run_query sigok.verteiltesysteme.net A +dnssec)"
pos_status="$(get_status "$pos_raw")"
pos_flags="$(get_flags "$pos_raw")"

pos_has_ad=false
flags_has "$pos_flags" "ad" && pos_has_ad=true

pos_ok=false
[[ "$pos_status" == "NOERROR" ]] && pos_ok=true

# ------------------------------------------------------------
# 3) DNSSEC negative
# ------------------------------------------------------------
neg_raw="$(run_query sigfail.verteiltesysteme.net A +dnssec)"
neg_status="$(get_status "$neg_raw")"

neg_ok=false
[[ "$neg_status" == "SERVFAIL" ]] && neg_ok=true

# ------------------------------------------------------------
# 4) DoH DNSSEC validation (optional)
# ------------------------------------------------------------
doh_ok=true
doh_note="not tested"

if [[ -n "$DOH_HOST" && -n "$DOH_PATH" ]]; then
  doh_ok=false
  doh_note=""

  doh_opts=(
    "+https=${DOH_HOST}${DOH_PATH}"
    "+https-get"
    "+tls-hostname=${DOH_HOST}"
  )

  doh_transport="$(kdig "${doh_opts[@]}" www.example.com A 2>&1 || true)"
  if ! grep -q "status: NOERROR" <<<"$doh_transport"; then
    doh_note="transport failed"
  else
    doh_pos="$(kdig "${doh_opts[@]}" sigok.verteiltesysteme.net A +dnssec 2>&1 || true)"
    if ! grep -q "status: NOERROR" <<<"$doh_pos" || ! grep -q "RRSIG" <<<"$doh_pos"; then
      doh_note="DNSSEC positive failed"
    else
      doh_neg="$(kdig "${doh_opts[@]}" sigfail.verteiltesysteme.net A +dnssec 2>&1 || true)"
      if grep -q "status: SERVFAIL" <<<"$doh_neg"; then
        doh_ok=true
        doh_note="DNS SERVFAIL"
      elif grep -q "HTTP session.*status: 5" <<<"$doh_neg"; then
        doh_ok=true
        doh_note="HTTP-level failure"
      else
        doh_note="no validation failure"
      fi
    fi
  fi
fi

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------
log "🧪 DNS health check against resolver ${RESOLVER}"
log "• Recursion: $([[ "$rec_ok" == true ]] && echo PASS || echo FAIL) (status=${rec_status}, flags=${rec_flags})"
log "• DNSSEC positive (sigok): $([[ "$pos_ok" == true ]] && echo PASS || echo FAIL) (status=${pos_status}, AD=${pos_has_ad})"
log "• DNSSEC negative (sigfail): $([[ "$neg_ok" == true ]] && echo PASS || echo FAIL) (status=${neg_status})"

if [[ -n "$DOH_HOST" && -n "$DOH_PATH" ]]; then
  log "• DoH DNSSEC (${DOH_HOST}): $([[ "$doh_ok" == true ]] && echo PASS || echo FAIL) (${doh_note})"
fi

# ------------------------------------------------------------
# Final verdict
# ------------------------------------------------------------
if [[ "$rec_ok" == true && "$pos_ok" == true && "$neg_ok" == true && ( -z "$DOH_HOST" || "$doh_ok" == true ) ]]; then
  log "✅ DNS recursion and DNSSEC enforcement are working correctly."
  log "ℹ️  Note: DNSSEC enforcement is verified by rejection of invalid signatures. The AD bit is not required to be present in responses from proxies or DoH frontends."
  exit 0
fi

if [[ "$rec_ok" != true ]]; then
  log "❌ Recursion failed — check resolver reachability and access-control."
fi

if [[ "$pos_ok" != true ]]; then
  log "❌ DNSSEC positive test failed — sigok did not resolve."
fi

if [[ "$neg_ok" != true ]]; then
  log "❌ DNSSEC negative test failed — sigfail must fail validation."
fi

if [[ -n "$DOH_HOST" && "$doh_ok" != true ]]; then
  log "❌ DoH DNSSEC test failed — expected SERVFAIL or HTTP-level failure."
fi

exit 1
