#!/bin/bash
# dns-health-check.sh
# Purpose: Verify local DNS recursion and DNSSEC validation with clear, plain-English output.
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

for cmd in dig sed grep logger awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd"; exit 2; }
done

export LC_ALL=C LANG=C

dig_q() {
  dig @"$RESOLVER" "$@" +tries=1 +time="$TIMEOUT_SECONDS" 2>&1 || true
}

# run_query: return raw dig output (empty on no output)
run_query() {
  local out
  out="$(dig_q "$@")"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    printf ''
  else
    printf '%s' "$out"
  fi
}

get_header() {
  # accepts raw text as $1 or stdin
  local raw line
  if [[ $# -gt 0 ]]; then raw="$1"; else raw="$(cat -)"; fi
  [[ -z "${raw:-}" ]] && return
  while IFS= read -r line; do
    case "$line" in
      *'->>HEADER<<-'* ) printf '%s\n' "${line#*->>HEADER<<- }"; return ;;
    esac
  done <<<"$raw"
}

get_status() {
  # Read raw dig output from $1 or stdin; print an uppercase RCODE token (NOERROR|SERVFAIL|NXDOMAIN) or nothing
  local raw header s
  if [[ $# -gt 0 ]]; then raw="$1"; else raw="$(cat -)"; fi
  [[ -z "${raw:-}" ]] && return

  # 1) Prefer the ->>HEADER<<- line if present and extract status: token (case-insensitive)
  header="$(printf '%s' "$raw" | sed -n '/->>HEADER<<-/p' | head -n1 || true)"
  if [[ -n "${header:-}" ]]; then
    s="$(printf '%s' "$header" | grep -oEi 'status:[[:space:]]*[A-Za-z]+' | head -n1 || true)"
    if [[ -n "${s:-}" ]]; then
      s="${s#*:}"
      s="$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      printf '%s' "$s"
      return
    fi
  fi

  # 2) Look for a status: token anywhere in the output (case-insensitive)
  s="$(printf '%s' "$raw" | grep -oEi 'status:[[:space:]]*[A-Za-z]+' | head -n1 || true)"
  if [[ -n "${s:-}" ]]; then
    s="${s#*:}"
    s="$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    printf '%s' "$s"
    return
  fi

  # 3) Final fallback: common RCODE tokens anywhere (case-insensitive)
  s="$(printf '%s' "$raw" | grep -oEi 'SERVFAIL|NOERROR|NXDOMAIN' | head -n1 || true)"
  if [[ -n "${s:-}" ]]; then
    printf '%s' "$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]')"
    return
  fi

  return
}

get_flags() {
  # $1 = raw dig output or stdin; returns "qr rd ra ad" style
  local raw line rest
  if [[ $# -gt 0 ]]; then raw="$1"; else raw="$(cat -)"; fi
  [[ -z "${raw:-}" ]] && return
  while IFS= read -r line; do
    case "$line" in
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

# 1) Recursion
rec_raw="$(run_query www.example.com A)"
rec_status="$(get_status "$rec_raw" || true)"
rec_flags="$(get_flags "$rec_raw" || true)"
rec_has_ra=false
if [[ -n "${rec_flags:-}" ]] && printf " %s " "$rec_flags" | grep -q ' ra '; then rec_has_ra=true; fi
rec_ok=false
if [[ "${rec_status:-}" == "NOERROR" && "$rec_has_ra" == "true" ]]; then rec_ok=true; fi

# 2) DNSSEC positive (sigok)
pos_raw="$(run_query sigok.verteiltesysteme.net A +dnssec)"
pos_status="$(get_status "$pos_raw" || true)"
pos_flags="$(get_flags "$pos_raw" || true)"
pos_has_ad=false
# AD detection: prefer flags, but also accept explicit "ad" mentions in output
if [[ -n "${pos_flags:-}" ]] && printf " %s " "$pos_flags" | grep -q ' ad '; then pos_has_ad=true; fi
if [[ "$pos_has_ad" != "true" ]] && printf '%s' "$pos_raw" | grep -qiE '\b ad\b|\bad\b'; then pos_has_ad=true; fi
pos_ok=false
if [[ "${pos_status:-}" == "NOERROR" && "$pos_has_ad" == "true" ]]; then pos_ok=true; fi

# 3) DNSSEC negative (sigfail)
neg_raw="$(run_query sigfail.verteiltesysteme.net A +dnssec)"
neg_status="$(get_status "$neg_raw" || true)"
neg_ok=false

# Diagnostic: if status is empty, log the first ~200 chars of raw output for analysis
if [[ -z "${neg_status:-}" ]]; then
  log "DEBUG: sigfail raw (first 200 chars):"
  # safely print raw with newlines collapsed and truncated
  printf '%s' "$neg_raw" | tr '\n' ' ' | sed -n '1,200p' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r line; do log "DEBUG: $line"; done
fi

# Primary: header token SERVFAIL
if [[ "${neg_status:-}" == "SERVFAIL" ]]; then neg_ok=true; fi
# Fallback: re-check using get_status (handles ->>HEADER<<- and other formats)
if [[ "$neg_ok" != "true" ]]; then
  n="$(get_status "$neg_raw" || true)"
  if [[ -n "${n:-}" && "$n" == "SERVFAIL" ]]; then neg_status="SERVFAIL"; neg_ok=true; fi
fi
if [[ "$neg_ok" != "true" ]]; then
  # loose token search
  if printf '%s' "$neg_raw" | grep -qiE '\bSERVFAIL\b'; then neg_status="SERVFAIL"; neg_ok=true; fi
fi


# Ensure defined under set -u
rec_status="${rec_status:-}"
pos_status="${pos_status:-}"
neg_status="${neg_status:-}"
rec_flags="${rec_flags:-}"
pos_flags="${pos_flags:-}"

# Output
log "🧪 DNS health check against resolver ${RESOLVER}"
log "• Recursion: $([[ "$rec_ok" == "true" ]] && echo PASS || echo FAIL) (status=${rec_status:-n/a}, flags=${rec_flags:-n/a})"
log "• DNSSEC positive (sigok): $([[ "$pos_ok" == "true" ]] && echo PASS || echo FAIL) (status=${pos_status:-n/a}, flags=${pos_flags:-n/a})"
log "• DNSSEC negative (sigfail): $([[ "$neg_ok" == "true" ]] && echo PASS || echo FAIL) (status=${neg_status:-n/a})"

# Guidance
if [[ "$rec_ok" == "true" && "$pos_ok" == "true" && "$neg_ok" == "true" ]]; then
  log "✅ DNS resolver is performing recursion and validating DNSSEC correctly."
  exit 0
fi

if [[ "$rec_ok" != "true" ]]; then
  log "❌ Recursion failed — check access-control, forward-zone config, and upstream reachability. Manual dig: dig @$RESOLVER www.example.com A"
fi
if [[ "$pos_ok" != "true" ]]; then
  log "❌ DNSSEC positive test failed — missing AD on sigok; check val-enable, upstreams, and system clock (NTP). Manual dig: dig @$RESOLVER sigok.verteiltesysteme.net A +dnssec"
fi
if [[ "$neg_ok" != "true" ]]; then
  log "❌ DNSSEC negative test failed — sigfail should SERVFAIL; if it returns NOERROR validation may be bypassed. Manual dig: dig @$RESOLVER sigfail.verteiltesysteme.net A +dnssec"
fi

exit 1
