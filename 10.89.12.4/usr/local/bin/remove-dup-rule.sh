#!/usr/bin/env bash
# remove-dup-rule.sh
# Remove duplicate identical rules from a chain, keeping the lowest-numbered copy.
# Usage:
#   sudo remove-dup-rule.sh FORWARD
#   sudo remove-dup-rule.sh POSTROUTING
#   sudo remove-dup-rule.sh FORWARD v6
#   sudo remove-dup-rule.sh POSTROUTING v6
#
# to deploy use 
#     sudo cp /home/julie/src/homelab/10.89.12.4/usr/local/bin/remove-dup-rule.sh /usr/local/bin/

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 CHAIN [v6]" >&2
  exit 2
fi

CHAIN="$1"
IS_V6=false
if [ "${2-}" = "v6" ]; then IS_V6=true; fi

if $IS_V6; then
  IPT_BIN="/usr/sbin/ip6tables-legacy"
else
  IPT_BIN="/usr/sbin/iptables-legacy"
fi

case "$CHAIN" in
  FORWARD) TABLE="filter" ;;
  POSTROUTING) TABLE="nat" ;;
  *) echo "Unsupported chain: $CHAIN. Supported: FORWARD, POSTROUTING" >&2; exit 2 ;;
esac

# quick check binary exists
if ! command -v "$IPT_BIN" >/dev/null 2>&1; then
  echo "Required binary not found: $IPT_BIN" >&2
  exit 3
fi

# test table availability for ip6tables nat (may not exist)
if $IS_V6 && [ "$TABLE" = "nat" ]; then
  if ! $IPT_BIN -t nat -L >/dev/null 2>&1; then
    echo "Warning: IPv6 nat table not available with $IPT_BIN -t nat; exiting." >&2
    exit 4
  fi
fi

# collect duplicate rule texts
mapfile -t dup_rules < <(
  "$IPT_BIN" -t "$TABLE" -S "$CHAIN" 2>/dev/null | grep -- "^-A $CHAIN " | sort | uniq -c | awk '$1>1 { $1=""; sub(/^ +/,""); print }'
)

if [ "${#dup_rules[@]}" -eq 0 ]; then
  echo "No duplicate exact rules found in $TABLE/$CHAIN for $IPT_BIN."
  exit 0
fi

echo "Found ${#dup_rules[@]} duplicated rule text(s) in $TABLE/$CHAIN ($IPT_BIN)."

for rule in "${dup_rules[@]}"; do
  echo
  echo "Rule text:"
  echo "  $rule"

  # list -S lines (ordered) for this chain
  mapfile -t s_lines < <("$IPT_BIN" -t "$TABLE" -S "$CHAIN" 2>/dev/null | grep -- "^-A $CHAIN ")

  nums=()
  for idx in "${!s_lines[@]}"; do
    if [ "${s_lines[$idx]}" = "$rule" ]; then
      nums+=( $((idx+1)) )
    fi
  done

  if [ "${#nums[@]}" -le 1 ]; then
    echo "  Only ${#nums[@]} occurrence found; nothing to delete."
    continue
  fi

  echo "  Occurrences at line numbers: ${nums[*]}"

  # Sort numbers descending into an array (use mapfile to avoid SC2207)
  mapfile -t sorted_desc < <(printf '%s\n' "${nums[@]}" | sort -rn)
  # to_delete = all but the lowest-numbered (which is the last element in sorted_desc)
  if [ "${#sorted_desc[@]}" -gt 1 ]; then
    to_delete=( "${sorted_desc[@]:0:${#sorted_desc[@]}-1}" )
  else
    to_delete=()
  fi

  echo "  Deleting duplicates (keeping lowest-numbered ${sorted_desc[-1]}): ${to_delete[*]}"
  for n in "${to_delete[@]}"; do
    echo "    Deleting $TABLE $CHAIN rule number $n"
    if $IS_V6; then
      "$IPT_BIN" -t "$TABLE" -D "$CHAIN" "$n"
    else
      # iptables-legacy: omit -t for filter deletions; include -t for nat
      if [ "$TABLE" = "filter" ]; then
        "$IPT_BIN" -D "$CHAIN" "$n"
      else
        "$IPT_BIN" -t "$TABLE" -D "$CHAIN" "$n"
      fi
    fi
  done
done

echo
echo "Done. Current $TABLE/$CHAIN rules (with line numbers) for $IPT_BIN:"
if $IS_V6; then
  "$IPT_BIN" -t "$TABLE" -L "$CHAIN" --line-numbers -n -v 2>/dev/null || true
else
  if [ "$TABLE" = "filter" ]; then
    "$IPT_BIN" -L "$CHAIN" --line-numbers -n -v
  else
    "$IPT_BIN" -t "$TABLE" -L "$CHAIN" --line-numbers -n -v
  fi
fi
