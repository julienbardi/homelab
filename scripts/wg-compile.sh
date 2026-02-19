#!/usr/bin/env bash
set -euo pipefail

# wg-compile.sh — validate staged CSV, allocate deterministic slots, render a plan snapshot
#
# Addressing contract (LOCKED):
#   - Interface wgN uses IPv4 prefix: 10.N.0.0/16
#   - Server on wgN:                10.N.0.1/16
#   - Clients on wgN:               10.N.A.B/32
#       A in [1..253], B in [2..254]
#       (never .0/.255, never .0.1 for clients)
#   - (A,B) is deterministic per base and identical across all interfaces
#
# IPv6 contract (LOCKED, Option B):
#   - Internal IPv6 uses ULA only (no delegated/global IPv6 in WireGuard).
#   - ULA prefix: fd89:7a3b:42c0::/48
#   - LAN ULA:    fd89:7a3b:42c0::/64
#   - wgN subnet: fd89:7a3b:42c0:N::/64   (N = decimal 1..15, embedded as a hextet)
#   - Server on wgN: fd89:7a3b:42c0:N::1/64
#   - Clients:       fd89:7a3b:42c0:N::A:B/128   (same A,B allocator as IPv4)
#
# Delegated/global IPv6 prefixes (e.g. 2a01:...) must never appear in compiled outputs.
#
# Authoritative input:
#   $WG_ROOT/input/clients.csv   (user,machine,iface)
#
# Compiled outputs (atomic):
#   $WG_ROOT/compiled/clients.lock.csv
#   $WG_ROOT/compiled/alloc.csv	(base,slot)
#   $WG_ROOT/compiled/plan.tsv	(AUTHORITATIVE for deploy; derived from clients.csv + alloc.csv)
#
# Notes:
# - Deterministic allocator with collision resolution.
# - alloc.csv is authoritative and never rewritten silently.
# - Fails loudly on any contract violation.

# Bootstrap contract:
# - homelab.env is the single absolute anchor
# - All other paths must be derived from variables defined there

# shellcheck disable=SC1091
source /volume1/homelab/homelab.env
: "${HOMELAB_DIR:?HOMELAB_DIR not set}"
: "${WG_ROOT:?WG_ROOT not set}"
die() { echo "wg-compile: ERROR: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "must run as root"

# WireGuard profile bitmask model (wg1..wg15)
BIT_LAN=0
BIT_V4=1
BIT_V6=2
BIT_FULL=3

ROOT="$WG_ROOT"
IN_DIR="$ROOT/input"
IN_CSV="$IN_DIR/clients.csv"

OUT_DIR="$ROOT/compiled"
ALLOC="$OUT_DIR/alloc.csv"
LOCK="$OUT_DIR/clients.lock.csv"
PLAN="$OUT_DIR/plan.tsv"

ENDPOINT_HOST_BASE="vpn.bardi.ch"
ENDPOINT_PORT_BASE="51420"

# Endpoint must remain a hostname (dynamic WAN IP); clients will resolve it.
# Note: if you ever hit a “FULL tunnel can’t resolve endpoint” bootstrap issue on a
# specific client platform, solve it explicitly there (not by freezing a dynamic IP).

# IPv6 (ULA-only) — authoritative constants
WG_ULA_PREFIX="fd89:7a3b:42c0"     # /48, written as 3 hextets
WG_ULA_LAN_CIDR="fd89:7a3b:42c0::/64"
WG_ULA_NAS="fd89:7a3b:42c0::4"
WG_ULA_WG_PREFIXLEN="64"

STAGE="$OUT_DIR/.staging.$$"
umask 077

wg_ifnum_sanity() {
	n="$1"
	if [ "$n" -lt 1 ] || [ "$n" -gt 15 ]; then
		die "invalid ifnum '$n' for wg subnet"
	fi
}

wg_ula_subnet6_for_ifnum() {
	ifnum="$1"
	wg_ifnum_sanity "$ifnum"
	# fd89:7a3b:42c0:<ifnum>::/64
	printf "%s:%s::/%s\n" "$WG_ULA_PREFIX" "$ifnum" "$WG_ULA_WG_PREFIXLEN"
}

server_addr6_for_ifnum() {
	ifnum="$1"
	wg_ifnum_sanity "$ifnum"
	# fd89:7a3b:42c0:<ifnum>::1/64
	printf "%s:%s::1/%s\n" "$WG_ULA_PREFIX" "$ifnum" "$WG_ULA_WG_PREFIXLEN"
}

client_addr6_for_ifnum_ab() {
	ifnum="$1"
	A="$2"
	B="$3"
	wg_ifnum_sanity "$ifnum"
	# fd89:7a3b:42c0:<ifnum>::A:B/128
	printf "%s:%s::%s:%s/128\n" "$WG_ULA_PREFIX" "$ifnum" "$A" "$B"
}
# profile is the authoritative intent model; iface numbers are no longer semantic.
profile_intent() {
	# profile format:
	# tunnel_<split|full>_lan_<0|1>_v4_<0|1>_v6_<0|1>

	local profile="$1"

	# Defensive defaults (required under set -u)
	TUNNEL_FULL=0
	ALLOW_LAN=0
	ALLOW_V4=0
	ALLOW_V6=0

	case "$profile" in
		tunnel_full_*)
			TUNNEL_FULL=1
			;;
		tunnel_split_*)
			TUNNEL_FULL=0
			;;
		*)
			echo "ERROR: invalid tunnel mode in profile: $profile" >&2
			return 1
			;;
	esac

	case "$profile" in
		*_lan_1_*) ALLOW_LAN=1 ;;
		*_lan_0_*) ALLOW_LAN=0 ;;
		*) echo "ERROR: invalid LAN bit in profile: $profile" >&2; return 1 ;;
	esac

	case "$profile" in
		*_v4_1_*) ALLOW_V4=1 ;;
		*_v4_0_*) ALLOW_V4=0 ;;
		*) echo "ERROR: invalid IPv4 bit in profile: $profile" >&2; return 1 ;;
	esac

	case "$profile" in
		*_v6_1) ALLOW_V6=1 ;;
		*_v6_0) ALLOW_V6=0 ;;
		*) echo "ERROR: invalid IPv6 bit in profile: $profile" >&2; return 1 ;;
	esac

	tunnel_mode="split"
	[ "$TUNNEL_FULL" -eq 1 ] && tunnel_mode="full"
	printf "%s %s %s %s\n" "$tunnel_mode" "$ALLOW_LAN" "$ALLOW_V4" "$ALLOW_V6"
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
	if [ "$s" -lt 0 ] || [ "$s" -ge "$SLOT_SPACE" ]; then
		die "invalid slot '$s'"
	fi
	A=$(( (s / 253) + 1 ))   # 1..253
	B=$(( (s % 253) + 2 ))   # 2..254
	printf "%s %s\n" "$A" "$B"
}

server_addr4_for_ifnum() { printf "10.%s.0.1/16\n" "$1"; }

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
	$1=="user" && $2=="machine" && $3=="iface" && $4=="profile" { next }
	NF < 4 { next }
	{
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4)
		base=$1 "-" $2
		print $1, $2, $3, $4, base
	}
' "$IN_CSV" | sort -u >"$NORM"

# Lock file
LOCK_TMP="$STAGE/clients.lock.csv"
{
	printf "user,machine,iface,profile\n"
	awk -F'\t' 'BEGIN{OFS=","}{print $1,$2,$3,$4}' "$NORM"
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
# Emit plan.tsv (authoritative)

PLAN_TMP="$STAGE/plan.tsv"
{
	printf "# GENERATED FILE — DO NOT EDIT\n"
	printf "node\tiface\tprofile\ttunnel_mode\tlan_access\tegress_v4\tegress_v6\tclient_addr_v4\tclient_addr_v6\tclient_allowed_ips_v4\tclient_allowed_ips_v6\tserver_allowed_ips_v4\tserver_allowed_ips_v6\tdns\n"

	while IFS="$(printf '\t')" read -r _ _ iface profile base; do
		ifnum="${iface#wg}"
		if [ "$ifnum" -lt 1 ] || [ "$ifnum" -gt 15 ]; then
			die "invalid iface wg${ifnum} — only wg1..wg15 are allowed"
		fi

		slot="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$STAGE/alloc.tsv")"
		[ -n "$slot" ] || die "no slot allocated for base '$base'"

		ab="$(ab_from_slot "$slot")"
		IFS=' ' read -r A B <<EOF
$ab
EOF
		unset ab

		client_addr4="10.${ifnum}.${A}.${B}/32"
		client_addr6="$(client_addr6_for_ifnum_ab "$ifnum" "$A" "$B")"

		# resolve intent from profile (explicit)
		set -- $(profile_intent "$profile")
		tunnel_mode="$1"
		lan_access="$2"
		egress_v4="$3"
		egress_v6="$4"

		# client AllowedIPs (explicit)
		client_allowed_v4="10.${ifnum}.0.0/16"
		client_allowed_v6="$(wg_ula_subnet6_for_ifnum "$ifnum")"

		[ "$lan_access" -eq 1 ] && {
			client_allowed_v4="${client_allowed_v4},10.89.12.0/24"
			client_allowed_v6="${client_allowed_v6},${WG_ULA_LAN_CIDR}"
		}

		[ "$tunnel_mode" = "full" ] && {
			[ "$egress_v4" -eq 1 ] && client_allowed_v4="${client_allowed_v4},0.0.0.0/1,128.0.0.0/1"
			[ "$egress_v6" -eq 1 ] && client_allowed_v6="${client_allowed_v6},::/1,8000::/1"
		}

		# server AllowedIPs: strictly client tunnel IPs only
		server_allowed_v4="$client_addr4"
		server_allowed_v6="$client_addr6"

		# DNS: per interface (NAS‑specific)
		dns="10.89.12.4,${WG_ULA_NAS}"

		printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
			"$base" "$iface" "$profile" \
			"$tunnel_mode" "$lan_access" "$egress_v4" "$egress_v6" \
			"$client_addr4" "$client_addr6" \
			"$client_allowed_v4" "$client_allowed_v6" \
			"$server_allowed_v4" "$server_allowed_v6" \
			"$dns"
	done <"$NORM"
} >"$PLAN_TMP"

if grep -qE '(^|[[:space:]])2a01:' "$PLAN_TMP"; then
	die "refusing to write plan: delegated/global IPv6 detected (2a01:...)"
fi

[ ! -e "$ROOT/out/clients" ] || {
	echo "wg-compile: ERROR: forbidden path exists: $ROOT/out/clients" >&2
	exit 1
}

install -m 0644 -o root -g root "$PLAN_TMP" "$PLAN"

install -m 0644 -o root -g root "$LOCK_TMP" "$LOCK"
install -m 0600 -o root -g root "$ALLOC_MERGED" "$ALLOC"