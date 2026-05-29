#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  log "❌ Must be run with sudo (root)."
  exit 1
fi

require_cmd dig sed grep logger awk head tr date stat expr

RESOLVER="${1:-127.0.0.1}"
PORT="53"

case "$RESOLVER" in
  127.0.0.1|10.89.12.4)
    PORT="15335"
    ;;
  ::1|fd89:7a3b:42c0::4)
    PORT="15335"
    ;;
  *)
    PORT="53"
    ;;
esac


TIMEOUT_SECONDS=2
MAX_RETRIES=2

export LC_ALL=C LANG=C

dig_q() {
  dig @"${RESOLVER}" -p "${PORT}" "$@" +tries=1 +time="${TIMEOUT_SECONDS}" 2>&1 || true
}

run_query() {
  local out tries=0
  set +e
  while :; do
    out="$(dig_q "$@")"
    if [[ -n "${out//[[:space:]]/}" ]] && ! grep -qi 'communications error' <<<"$out"; then
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
  echo "$raw" | sed -n '/->>HEADER<<-/s/.*status: \([A-Z]*\).*/\1/p' | head -n1 | tr '[:lower:]' '[:upper:]'
}

get_flags() {
  local raw="$1"
  echo "$raw" | sed -n 's/.*;; flags: \([^;]*\).*/\1/p'
}

flags_has() {
  printf ' %s ' "$1" | grep -q " $2 "
}

# -------------------------------
# RUN TESTS
# -------------------------------
tmpdir="$(mktemp -p /run -d homelab.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

run_query rec www.example.com A >"$tmpdir/rec.out" 2>&1
run_query pos sigok.verteiltesysteme.net A +dnssec >"$tmpdir/pos.out" 2>&1
run_query neg sigfail.verteiltesysteme.net A +dnssec >"$tmpdir/neg.out" 2>&1

rec_raw=$(cat "$tmpdir/rec.out")
pos_raw=$(cat "$tmpdir/pos.out")
neg_raw=$(cat "$tmpdir/neg.out")

rec_status="$(get_status "$rec_raw")"
rec_flags="$(get_flags "$rec_raw")"
rec_ok=false
if [[ "$rec_status" == "NOERROR" ]] && flags_has "$rec_flags" "ra"; then
  rec_ok=true
fi

pos_status="$(get_status "$pos_raw")"
pos_ok=false
[[ "$pos_status" == "NOERROR" ]] && pos_ok=true

neg_status="$(get_status "$neg_raw")"
neg_ok=false
neg_inconclusive=false
case "$neg_status" in
  SERVFAIL) neg_ok=true ;;
  EMPTY|UNKNOWN) neg_inconclusive=true ;;
  *) neg_ok=false ;;
esac

# -------------------------------
# OUTPUT
# -------------------------------
log "📊 DNS health check against resolver ${RESOLVER}"
log "$([[ "$rec_ok" == true ]] && echo ✅ || echo ❌) Recursion (status=${rec_status}, flags=${rec_flags})"
log "$([[ "$pos_ok" == true ]] && echo ✅ || echo ❌) DNSSEC positive (sigok: status=${pos_status})"

if [[ "$neg_ok" == true ]]; then
  log "✅ DNSSEC negative (sigfail: status=${neg_status})"
elif [[ "$neg_inconclusive" == true ]]; then
  log "⚠️  DNSSEC negative inconclusive (status=${neg_status})"
else
  log "❌ DNSSEC negative (sigfail: status=${neg_status})"
fi

# -------------------------------
# FINAL VERDICT
# -------------------------------
if [[ "$rec_ok" == true && "$pos_ok" == true && "$neg_ok" == true ]]; then
  log "✅ DNS recursion and DNSSEC enforcement are working correctly."
  exit 0
fi

exit 1
