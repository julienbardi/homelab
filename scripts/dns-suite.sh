#!/usr/bin/env bash
set -euo pipefail

# Required tools
for c in dig sed grep awk mktemp; do
  command -v "$c" >/dev/null 2>&1 || {
    echo "missing required command: $c" >&2
    exit 1
  }
done

LAN_NAS="${LAN_NAS:-10.89.12.4}"
LAN6_NAS="${LAN6_NAS:-fd89:7a3b:42c0::4}"
LAN_ROUTER="${LAN_ROUTER:-10.89.12.1}"

RESOLVERS=(
  "loopback4|127.0.0.1|15335"
  "loopback6|::1|15335"
  "nas4|${LAN_NAS}|15335"
  "nas6|${LAN6_NAS}|15335"
  "router4|${LAN_ROUTER}|53"
  "router6_wan|SKIP|0"
)

DNSSEC_DOMAIN="cloudflare.com"

test_resolver() {
  local name="$1" ip="$2" port="$3" outfile="$4"

  if [[ "$ip" == "SKIP" ]]; then
    printf "SKIP" > "$outfile"
    return 0
  fi

  local dig_out
  dig_out="$(dig +dnssec +adflag +timeout=2 +tries=1 @"$ip" -p "$port" "$DNSSEC_DOMAIN" A 2>&1 || true)"

  # Recursion OK if we see an A record
  local rec_ok=false
  if printf '%s' "$dig_out" | grep -Eq 'IN[[:space:]]+A'; then
    rec_ok=true
  fi

  # DNSSEC OK if we see an RRSIG
  local rrsig_ok=false
  if printf '%s' "$dig_out" | grep -q 'RRSIG'; then
    rrsig_ok=true
  fi

  # AD bit OK if flags contain " ad "
  local ad_ok=false
  if printf '%s' "$dig_out" \
      | grep -E '^;; flags:' \
      | grep -Eq ' ad( |$)'; then
    ad_ok=true
  fi

  if [[ "$name" == "router4" ]]; then
    # router4 only needs recursion
    if [[ "$rec_ok" == true ]]; then
      printf "ROUTER4_OK" > "$outfile"
    else
      printf "FAIL" > "$outfile"
    fi
    return 0
  fi

  # Encode detailed state
  printf "%s|%s|%s" "$rec_ok" "$rrsig_ok" "$ad_ok" > "$outfile"
}

echo "📊 Running dig-based DNS suite (AD + RRSIG reporting)"
tmpdir="$(mktemp -d)"
declare -A OUTFILES

# Launch all resolvers in parallel
for entry in "${RESOLVERS[@]}"; do
  IFS='|' read -r name ip port <<<"$entry"
  outfile="$tmpdir/$name.out"
  OUTFILES["$name"]="$outfile"
  test_resolver "$name" "$ip" "$port" "$outfile" &
done

wait

overall_ok=true
echo
echo "📊 DNS Suite Results"
echo "---------------------"

# Ordered, deterministic output
for entry in "${RESOLVERS[@]}"; do
  IFS='|' read -r name ip port <<<"$entry"
  result="$(cat "${OUTFILES[$name]}")"

  if [[ "$result" == "SKIP" ]]; then
    echo "⚪ router6_wan (skipped — WAN IPv6 address is not a DNS server)"
    continue
  fi

  if [[ "$result" == "ROUTER4_OK" ]]; then
    echo "🟦 router4 (OK — recursion only; DNSSEC validation done by Unbound)"
    continue
  fi

  IFS='|' read -r rec_ok rrsig_ok ad_ok <<<"$result"

  if [[ "$rec_ok" == true && "$rrsig_ok" == true ]]; then
    if [[ "$ad_ok" == true ]]; then
      echo "🟩 $name (recursion OK, RRSIG OK, AD OK)"
    else
      echo "🟨 $name (recursion OK, RRSIG OK, AD missing)"
    fi
  else
    echo "❌ $name (rec=$rec_ok rrsig=$rrsig_ok ad=$ad_ok)"
    overall_ok=false
  fi
done

rm -rf "$tmpdir"

echo
$overall_ok && { echo "🎉 All resolvers healthy"; exit 0; }
echo "❌ One or more resolvers failed"; exit 1
