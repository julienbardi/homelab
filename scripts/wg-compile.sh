#!/bin/sh
set -eu

# wg-compile.sh — validate staged CSV, allocate deterministic slots, render a plan snapshot
#
# Addressing contract (LOCKED):
#   - Interface wgN uses IPv4 prefix: 10.N.0.0/16
#   - Server on wgN:                10.N.0.1/16
#   - Clients on wgN:               10.N.A.B/16
#       A in [1..253], B in [2..254]
#       (never .0/.255, never .0.1 for clients)
#   - (A,B) is deterministic per base and identical across all interfaces
#
# IPv6 is symmetric and embeds the same (A,B):
#   wgN (N=1..15): 2a01:8b81:4800:9c0X::A:B  (X = hex(N))
#   2a01:8b81:4800:9c00::/64 is the LAN and connot be used for Wireguard subnets.
#   wg1 -> 2a01:8b81:4800:9c01::/64
#   ...
#   wg10-> 2a01:8b81:4800:9c0a::/64
#   wg15-> 2a01:8b81:4800:9c0f::/64
#
# Authoritative input:
#   /volume1/homelab/wireguard/input/clients.csv   (user,machine,iface)
#
# Compiled outputs (atomic):
#   /volume1/homelab/wireguard/compiled/clients.lock.csv
#   /volume1/homelab/wireguard/compiled/alloc.csv   (base,slot)
#   /volume1/homelab/wireguard/compiled/plan.tsv   (NON-AUTHORITATIVE, derived)
#
# Notes:
# - Deterministic allocator with collision resolution.
# - alloc.csv is authoritative and never rewritten silently.
# - Fails loudly on any contract violation.

# --------------------------------------------------------------------

# WireGuard profile bitmask model (wg1..wg15)
BIT_LAN=0
BIT_V4=1
BIT_V6=2
BIT_FULL=3

ROOT="/volume1/homelab/wireguard"
IN_DIR="$ROOT/input"
IN_CSV="$IN_DIR/clients.csv"

OUT_DIR="$ROOT/compiled"
ALLOC="$OUT_DIR/alloc.csv"
LOCK="$OUT_DIR/clients.lock.csv"
PLAN="$OUT_DIR/plan.tsv"

ENDPOINT_HOST_BASE="vpn.bardi.ch"
ENDPOINT_PORT_BASE="51420"

TAB="$(printf '\t')"
STAGE="$OUT_DIR/.staging.$$"
umask 077

die() { echo "wg-compile: ERROR: $*" >&2; exit 1; }

wg_hextet_from_ifnum() {
	n="$1"
	[ "$n" -ge 1 ] && [ "$n" -le 15 ] || die "invalid ifnum '$n' for wg subnet"
	printf "9c0%x" "$n"
}

# --------------------------------------------------------------------
# Deterministic allocator helpers

SLOT_SPACE=$((253 * 253))   # 64009

hex8_from_sha256() {
	printf "%s" "$1" | sha256sum | awk '{print substr($1,1,8)}'
}

slot_from_base() {
	h="$(hex8_from_sha256 "$1")"
	v=$((16#$h))
	printf "%s\n" $((v % SLOT_SPACE))
}

ab_from_slot() {
	s="$1"
	[ "$s" -ge 0 ] && [ "$s" -lt "$SLOT_SPACE" ] || die "invalid slot '$s'"
	A=$(( (s / 253) + 1 ))   # 1..253
	B=$(( (s % 253) + 2 ))   # 2..254
	printf "%s %s\n" "$A" "$B"
}

server_addr4_for_ifnum() { printf "10.%s.0.1/16\n" "$1"; }
server_addr6_for_ifnum() {
	ifnum="$1"
	hextet="$(wg_hextet_from_ifnum "$ifnum")"
	printf "2a01:8b81:4800:%s::1/128\n" "$hextet"
}


# --------------------------------------------------------------------

mkdir -p "$IN_DIR" "$OUT_DIR"
[ -f "$IN_CSV" ] || die "missing input CSV: $IN_CSV"

# Ensure allocator exists and schema is correct
if [ ! -f "$ALLOC" ]; then
	printf "%s\n" "base,slot" >"$ALLOC"
	chmod 600 "$ALLOC"
else
	hdr="$(head -n 1 "$ALLOC")"
	[ "$hdr" = "base,slot" ] || die "alloc.csv uses legacy schema '$hdr' — migrate manually"
fi

mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT INT HUP TERM

# --------------------------------------------------------------------
# Normalize input

NORM="$STAGE/clients.norm.tsv"
awk -F',' '
	BEGIN { OFS="\t" }
	/^[[:space:]]*#/ { next }
	$1=="user" && $2=="machine" && $3=="iface" { next }
	NF < 3 { next }
	{
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
		base=$1 "-" $2
		print $1, $2, $3, base
	}
' "$IN_CSV" | sort -u >"$NORM"

# Lock file
LOCK_TMP="$STAGE/clients.lock.csv"
{
	printf "user,machine,iface\n"
	awk -F'\t' 'BEGIN{OFS=","}{print $1,$2,$3}' "$NORM"
} >"$LOCK_TMP"

# --------------------------------------------------------------------
# Allocator merge

ALLOC_MERGED="$STAGE/alloc.merged.csv"
{
	printf "base,slot\n"
	awk -F',' 'NR>1{print}' "$ALLOC"
} >"$ALLOC_MERGED"

awk -F'\t' '{print $4}' "$NORM" | sort -u | while read -r base; do
	if ! awk -F',' -v b="$base" 'NR>1 && $1==b{found=1} END{exit(found?0:1)}' "$ALLOC_MERGED"; then
		slot="$(slot_from_base "$base")"
		while awk -F',' -v s="$slot" 'NR>1 && $2==s{found=1} END{exit(found?0:1)}' "$ALLOC_MERGED"; do
			slot=$(( (slot + 1) % SLOT_SPACE ))
		done
		printf "%s,%s\n" "$base" "$slot" >>"$ALLOC_MERGED"
	fi
done

awk -F',' 'NR>1{printf "%s\t%s\n",$1,$2}' "$ALLOC_MERGED" >"$STAGE/alloc.tsv"

# --------------------------------------------------------------------
# Emit plan.tsv

PLAN_TMP="$STAGE/plan.tsv"
{
	printf "# GENERATED FILE — DO NOT EDIT\n"
	printf "base\tiface\tslot\tdns\tclient_addr4\tclient_addr6\tAllowedIPs_client\tAllowedIPs_server\tendpoint\n"

	while IFS=$'\t' read -r user machine iface base; do
		ifnum="${iface#wg}"
		if [ "$ifnum" -lt 1 ] || [ "$ifnum" -gt 15 ]; then
			die "invalid iface wg${ifnum} — only wg1..wg15 are allowed"
		fi

		slot="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$STAGE/alloc.tsv")"
		set -- $(ab_from_slot "$slot")
		A="$1"; B="$2"

		client_addr4="10.${ifnum}.${A}.${B}/16"
		client_addr6="2a01:8b81:4800:$(wg_hextet_from_ifnum "$ifnum")::${A}:${B}/128"
  	
		server_addr4="$(server_addr4_for_ifnum "$ifnum")"
		server_addr6="$(server_addr6_for_ifnum "$ifnum")"

		allowed_server="${client_addr4}, ${client_addr6}"

		has_lan=$(( (ifnum >> BIT_LAN) & 1 ))
		has_v4=$(( (ifnum >> BIT_V4) & 1 ))
		has_v6=$(( (ifnum >> BIT_V6) & 1 ))
		is_full=$(( (ifnum >> BIT_FULL) & 1 ))

		# AllowedIPs for the client:
		# - Always include wgN subnets (v4 + v6) so the tunnel itself is routable.
		# - Add LAN prefixes when BIT_LAN is set.
		# - Add default routes only when BIT_FULL is set, gated by the inet bits.
		allowed_client="10.${ifnum}.0.0/16, 2a01:8b81:4800:$(wg_hextet_from_ifnum "$ifnum")::/64"

		if [ "$has_lan" -eq 1 ]; then
			allowed_client="${allowed_client}, 10.89.12.0/24, 2a01:8b81:4800:9c00::/64"
		fi

		if [ "$is_full" -eq 1 ]; then
			[ "$has_v4" -eq 1 ] || die "iface ${iface} sets FULL without inet-v4 bit"
			[ "$has_v6" -eq 1 ] || die "iface ${iface} sets FULL without inet-v6 bit"
			allowed_client="${allowed_client}, 0.0.0.0/0, ::/0"
		fi

		endpoint="${ENDPOINT_HOST_BASE}:$((ENDPOINT_PORT_BASE + ifnum))"

		dns=""
		if [ "$has_lan" -eq 1 ] || [ "$is_full" -eq 1 ]; then
			dns="10.89.12.4, 2a01:8b81:4800:9c00::4"
		fi
		printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
			"$base" "$iface" "$slot" \
			"$dns" \
			"$client_addr4" "$client_addr6" \
			"$allowed_client" "$allowed_server" \
			"$endpoint"
	done <"$NORM"
} >"$PLAN_TMP"

mv -f "$PLAN_TMP" "$PLAN"
mv -f "$LOCK_TMP" "$LOCK"
mv -f "$ALLOC_MERGED" "$ALLOC"

chmod 600 "$PLAN" "$LOCK" "$ALLOC"

echo "wg-compile: OK"
