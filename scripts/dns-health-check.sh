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
#   - [resolver_ip] applies only to classic DNS tests (sections 1-3).
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

# Auto-append port if querying local Unbound
if [[ "$RESOLVER" == "127.0.0.1" || "$RESOLVER" == "10.89.12.4" ]]; then
    if [[ ! "$RESOLVER" =~ "-p" ]]; then
        RESOLVER="$RESOLVER -p 5335"
    fi
fi

TIMEOUT_SECONDS=2
MAX_RETRIES=2

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
  # shellcheck disable=SC2086
  dig @${RESOLVER} "$@" +tries=1 +time="$TIMEOUT_SECONDS" 2>&1 || true
}

run_query() {
  local out tries=0
  set +e
  while :; do
    out="$(dig_q "$@")"
    if [[ -n "${out//[[:space:]]/}" ]] && ! grep -qEi 'communications error' <<<"$out"; then
      printf '%s' "$out"
      set -e
      return 0
    fi
    tries=$((tries+1))
    if [[ $tries -ge $MAX_RETRIES ]]; then
      printf '%s' "$out"
      set -e
      return 0
    fi
    sleep 1
  done
}

get_status() {
  local raw="$1"
  [[ -z "$raw" ]] && echo "EMPTY" && return

  # Extract the status word by looking for the word immediately following 'status:'
  local s
  s=$(echo "$raw" | sed -n '/->>HEADER<<-/s/.*status: \([A-Z]*\).*/\1/p' | head -n1)

  # If sed failed, fallback to awk for standard field extraction
  if [[ -z "$s" ]]; then
    s=$(echo "$raw" | awk -F'status: ' '/->>HEADER<<-/ {print $2}' | awk '{print $1}' | tr -d ',')
  fi

  echo "${s:-UNKNOWN}" | tr '[:lower:]' '[:upper:]'
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
# Parallel query execution
# ------------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

run_query_bg() {
  local name="$1"; shift
  run_query "$@" >"$tmpdir/$name.out" 2>&1
}

run_query_bg rec www.example.com A &
run_query_bg pos sigok.verteiltesysteme.net A +dnssec &
run_query_bg neg sigfail.verteiltesysteme.net A +dnssec &
wait

# Use this more robust reading method
rec_raw=$(cat "$tmpdir/rec.out" 2>/dev/null || true)
pos_raw=$(cat "$tmpdir/pos.out" 2>/dev/null || true)
neg_raw=$(cat "$tmpdir/neg.out" 2>/dev/null || true)

# ------------------------------------------------------------
# 1) Recursion
# ------------------------------------------------------------
rec_status="$(get_status "$rec_raw")"
rec_flags="$(get_flags "$rec_raw")"

rec_ok=false
if [[ "$rec_status" == "NOERROR" ]] && flags_has "$rec_flags" "ra"; then
  rec_ok=true
fi

# ------------------------------------------------------------
# 2) DNSSEC positive
# ------------------------------------------------------------
pos_status="$(get_status "$pos_raw")"
pos_flags="$(get_flags "$pos_raw")"

pos_has_ad=false
flags_has "$pos_flags" "ad" && pos_has_ad=true

pos_ok=false
[[ "$pos_status" == "NOERROR" ]] && pos_ok=true

# ------------------------------------------------------------
# 3) DNSSEC negative
# ------------------------------------------------------------
neg_status="$(get_status "$neg_raw")"

neg_ok=false
# Only pass if the resolver explicitly refuses the invalid signature (SERVFAIL)
if [[ "$neg_status" == "SERVFAIL" ]]; then
  neg_ok=true
fi

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
log "🩺 DNS health check against resolver ${RESOLVER}"
log "$([[ "$rec_ok" == true ]] && echo ✅ || echo ❌) Recursion (status=${rec_status}, flags=${rec_flags})"
log "$([[ "$pos_ok" == true ]] && echo ✅ || echo ❌) DNSSEC positive (sigok: status=${pos_status}, AD=${pos_has_ad})"
log "$([[ "$neg_ok" == true ]] && echo ✅ || echo ❌) DNSSEC negative (sigfail: status=${neg_status})"

if [[ -n "$DOH_HOST" && -n "$DOH_PATH" ]]; then
    log "$([[ "$doh_ok" == true ]] && echo ✅ || echo ❌) DoH DNSSEC (${DOH_HOST}): ${doh_note}"
fi

# Capture the query time from dig output
query_time=$(grep "Query time:" <<<"$rec_raw" | awk '{print $4}' | head -n1)
if [[ "$rec_ok" == true && -n "$query_time" && "$query_time" -gt 500 ]]; then
    log "⚠️  Cache appears COLD (Latency: ${query_time}ms)"
fi

# ------------------------------------------------------------
# Final verdict
# ------------------------------------------------------------
if [[ "$rec_ok" == true && "$pos_ok" == true && "$neg_ok" == true && ( -z "$DOH_HOST" || "$doh_ok" == true ) ]]; then
    log "✅ DNS recursion and DNSSEC enforcement are working correctly."
    log "ℹ️  Note: DNSSEC enforcement verified by rejection of invalid signatures."
    exit 0
fi

# Error reporting
[[ "$rec_ok" != true ]] && log "❌ Recursion failed — check reachability/ACL."
[[ "$pos_ok" != true ]] && log "❌ DNSSEC positive test failed — sigok did not resolve."
[[ "$neg_ok" != true ]] && log "❌ DNSSEC negative test failed — invalid signatures accepted."
[[ -n "$DOH_HOST" && "$doh_ok" != true ]] && log "❌ DoH DNSSEC test failed — expected SERVFAIL/HTTP-5xx."

exit 1