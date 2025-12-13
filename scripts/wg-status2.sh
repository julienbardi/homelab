#!/usr/bin/env bash
# scripts/wg-status2.sh
# Show WireGuard peer status with resolved names from /etc/wireguard/client-map.csv
# Prefers pubkey->name mapping; falls back to iface|AllowedIP. Shows unmatched peers separately.
# Shows full peer public key and LISTEN (interface listen port) before ENDPOINT.
set -euo pipefail
IFS=$'\n\t'

MAP_FILE="/etc/wireguard/client-map.csv"
FULL=1   # always show full AllowedIPs

trim() { local s="$1"; local n="$2"; [ "${#s}" -gt "$n" ] && printf '%s…' "${s:0:$n}" || printf '%s' "$s"; }

# Build maps from CSV:
# - NAME_BY_PUBKEY[pubkey]=name
# - NAME_BY_IFACE_IP["iface|ip"]=name
declare -A NAME_BY_PUBKEY
declare -A NAME_BY_IFACE_IP

if sudo test -f "$MAP_FILE" >/dev/null 2>&1; then
  # Read CSV robustly; support two formats:
  # 1) name,iface,ip4,ip6
  # 2) name,iface,pubkey,ip4,ip6
  while IFS=',' read -r name iface f3 f4 f5; do
	name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	iface="$(printf '%s' "$iface" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	f3="$(printf '%s' "$f3" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	f4="$(printf '%s' "$f4" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	f5="$(printf '%s' "$f5" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

	# Detect if f3 looks like a WireGuard public key (base64-like, often ends with '=')
	if [[ "$f3" =~ [A-Za-z0-9+/]{10,}={0,2}$ ]]; then
	  pubkey="$f3"
	  [ -n "$pubkey" ] && NAME_BY_PUBKEY["$pubkey"]="$name"
	  [ -n "$f4" ] && NAME_BY_IFACE_IP["${iface}|${f4}"]="$name"
	  [ -n "$f5" ] && NAME_BY_IFACE_IP["${iface}|${f5}"]="$name"
	else
	  [ -n "$f3" ] && NAME_BY_IFACE_IP["${iface}|${f3}"]="$name"
	  [ -n "$f4" ] && NAME_BY_IFACE_IP["${iface}|${f4}"]="$name"
	  [ -n "$f5" ] && NAME_BY_IFACE_IP["${iface}|${f5}"]="$name"
	fi
  done < <(sudo cat "$MAP_FILE")
fi

# Determine interfaces (detect wireguard links)
ifaces_detected=()
mapfile -t ifaces_detected < <(ip -o link show type wireguard 2>/dev/null | awk -F': ' '{print $2}')
if [ ${#ifaces_detected[@]} -eq 0 ]; then
  IFACES=(wg0 wg1 wg2 wg3 wg4 wg5 wg6 wg7)
else
  IFACES=("${ifaces_detected[@]}")
fi

# Temp files for matched and unmatched rows
TMP_MATCH="$(mktemp)"
TMP_UNMATCH="$(mktemp)"
trap 'rm -f "$TMP_MATCH" "$TMP_UNMATCH"' EXIT

# Collect rows
for ifa in "${IFACES[@]}"; do
  ip link show "$ifa" >/dev/null 2>&1 || continue

  # fetch interface listen port (may be empty)
  iface_listen="$(sudo wg show "$ifa" listen-port 2>/dev/null || true)"
  iface_listen="$(printf '%s' "$iface_listen" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Normalize wg dump into: pubkey<TAB>endpoint<TAB>allowed_ips
  while IFS=$'\t' read -r pub endpoint allowed; do
	allowed_trim="$(printf '%s' "$allowed" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	if [ -z "$allowed_trim" ] || [ "$allowed_trim" = "off" ] || [ "$allowed_trim" = "0" ]; then
	  continue
	fi

	resolved=""
	# 1) Prefer pubkey mapping
	if [ -n "$pub" ] && [ -n "${NAME_BY_PUBKEY[$pub]:-}" ]; then
	  resolved="${NAME_BY_PUBKEY[$pub]}"
	fi

	# 2) Fallback: match iface|allowed_ip
	if [ -z "$resolved" ]; then
	  IFS=',' read -ra AIPS <<< "$allowed_trim"
	  for a in "${AIPS[@]}"; do
		a="$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		key="${ifa}|${a}"
		if [ -n "${NAME_BY_IFACE_IP[$key]:-}" ]; then
		  resolved="${NAME_BY_IFACE_IP[$key]}"
		  break
		fi
	  done
	fi

	# 3) Fallback: match IP across any iface
	if [ -z "$resolved" ]; then
	  for a in "${AIPS[@]}"; do
		a="$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		for k in "${!NAME_BY_IFACE_IP[@]}"; do
		  ip="${k#*|}"
		  if [ "$ip" = "$a" ]; then
			resolved="${NAME_BY_IFACE_IP[$k]}"
			break 2
		  fi
		done
	  done
	fi

	pub_full="$pub"
	# endpoint: peer endpoint string (may be "(none)" or empty)
	endpoint_trim="$(printf '%s' "$endpoint" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	# Write to matched or unmatched temp file (tab-separated)
	if [ -n "$resolved" ]; then
	  # matched: IFACE<TAB>NAME<TAB>PUBKEY_FULL<TAB>LISTEN<TAB>ENDPOINT<TAB>ALLOWEDIPS
	  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ifa" "$resolved" "$pub_full" "$iface_listen" "$endpoint_trim" "$allowed_trim" >> "$TMP_MATCH"
	else
	  # unmatched: tag as (unmatched) and include full pubkey
	  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ifa" "(unmatched)" "$pub_full" "$iface_listen" "$endpoint_trim" "$allowed_trim" >> "$TMP_UNMATCH"
	fi
  done < <(sudo wg show "$ifa" dump 2>/dev/null | awk -F'\t' 'NF>=4 {print $1 "\t" $3 "\t" $4}')
done

# Print header (adjust widths for full pubkey)
printf '%-6s %-20s %-44s %-8s %-22s %s\n' "Iface" "Name" "Peer public key" "Port" "Endpoint" "Allowed IPs"
printf '%-6s %-20s %-44s %-8s %-22s %s\n' "------" "--------------------" "--------------------------------------------" "--------" "----------------------" "----------------"

# Print matched rows sorted by NAME then IFACE
if [ -s "$TMP_MATCH" ]; then
  sort -t$'\t' -k2,2 -k1,1 "$TMP_MATCH" | while IFS=$'\t' read -r ifa name pub_full listen endpoint allowed; do
	listen_display="${listen:--}"
	endpoint_display="${endpoint:--}"
	printf '%-6s %-20s %-44s %-8s %-22s %s\n' "$ifa" "$name" "$pub_full" "$listen_display" "$endpoint_display" "$allowed"
  done
fi

# Print unmatched peers separately (if any)
if [ -s "$TMP_UNMATCH" ]; then
  echo
  printf '%s\n' "Unmatched peers (no name found in client-map.csv):"
  printf '%-6s %-20s %-44s %-8s %-22s %s\n' "Iface" "Name" "Peer public key" "Port" "Endpoint" "Allowed IPs"
  printf '%-6s %-20s %-44s %-8s %-22s %s\n' "------" "--------------------" "--------------------------------------------" "--------" "----------------------" "----------------"
  sort -t$'\t' -k1,1 "$TMP_UNMATCH" | while IFS=$'\t' read -r ifa tag pub_full listen endpoint allowed; do
	listen_display="${listen:--}"
	endpoint_display="${endpoint:--}"
	printf '%-6s %-20s %-44s %-8s %-22s %s\n' "$ifa" "$tag" "$pub_full" "$listen_display" "$endpoint_display" "$allowed"
  done
fi
