#!/bin/sh
set -eu

# wg-compile.sh — validate staged CSV, allocate stable host IDs, render a plan snapshot
# Authoritative input:
#   /volume1/homelab/wireguard/input/clients.csv   (user,machine,iface)
#
# Compiled outputs (atomic):
#   /volume1/homelab/wireguard/compiled/clients.lock.csv
#   /volume1/homelab/wireguard/compiled/alloc.csv
#   /volume1/homelab/wireguard/compiled/plan.tsv   (NON-AUTHORITATIVE, derived)
#
# Notes:
# - iface is the profile (wg0..wg7). No tags/overrides.
# - Deterministic hostid: stateful allocator in alloc.csv, never changes once assigned.
# - Fails loudly; does not modify deployed state.

ROOT="/volume1/homelab/wireguard"
IN_DIR="$ROOT/input"
IN_CSV="$IN_DIR/clients.csv"

OUT_DIR="$ROOT/compiled"
ALLOC="$OUT_DIR/alloc.csv"
LOCK="$OUT_DIR/clients.lock.csv"
PLAN="$OUT_DIR/plan.tsv"

# DNS selection rationale:
#
# Clients always send DNS queries through the WireGuard tunnel.
# The primary resolver is the WireGuard server itself (127.0.0.1).
#
# Fallback behavior depends on client profile:
#
#   - LAN clients:
#       Primary:  127.0.0.1        (WG server local resolver)
#       Fallback: 10.89.12.1       (LAN router DNS)
#
#   - Non-LAN / roaming clients:
#       Primary:  127.0.0.1        (WG server local resolver)
#       Fallback: 9.9.9.9          (public resolver)
#
# IPv6 follows the same model with equivalent addresses.
#
# Resolver order is explicit; clients will try entries in order.
# IPv4 vs IPv6 preference is left to the client OS resolver policy.
ENDPOINT_HOST_BASE="vpn.bardi.ch"
ENDPOINT_PORT_BASE="51420"

STAGE="$OUT_DIR/.staging.$$"
umask 077

die() { echo "wg-compile: ERROR: $*" >&2; exit 1; }

mkdir -p "$IN_DIR" "$OUT_DIR"
[ -f "$IN_CSV" ] || die "missing input CSV: $IN_CSV"

# Ensure allocator exists
if [ ! -f "$ALLOC" ]; then
	printf "%s\n" "base,hostid" >"$ALLOC"
	chmod 600 "$ALLOC"
fi

mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' EXIT INT HUP TERM


# --- normalization + allocation (required producers for plan rendering) ---

# 1) Normalize clients.csv into a TSV used by the plan renderer:
#    user<TAB>machine<TAB>iface<TAB>base
NORM="$STAGE/clients.norm.tsv"
awk -F',' '
		BEGIN { OFS="\t" }

		# Skip comments
		/^[[:space:]]*#/ { next }

		# Skip CSV header wherever it appears
		$1=="user" && $2=="machine" && $3=="iface" { next }

		# Skip malformed rows
		NF < 3 { next }

		{
				user=$1
				machine=$2
				iface=$3

				gsub(/^[[:space:]]+|[[:space:]]+$/, "", user)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", machine)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", iface)

				base=user "-" machine
				print user, machine, iface, base
		}
' "$IN_CSV" | sort -u >"$NORM"


# 2) Lock file (authoritative snapshot of normalized intent, CSV)
LOCK_TMP="$STAGE/clients.lock.csv"
{
	printf "%s\n" "user,machine,iface"
	awk -F'\t' 'BEGIN{OFS=","} {print $1,$2,$3}' "$NORM"
} >"$LOCK_TMP"

# 3) Allocator merge: ensure every base has a stable hostid
#    Existing allocator: $ALLOC (CSV: base,hostid)
#    New merged allocator output path is fixed by later mv:
#      mv -f "$STAGE/alloc.merged.csv" "$ALLOC"
ALLOC_MERGED="$STAGE/alloc.merged.csv"

# Seed merged allocator with header + existing rows
{
	printf "%s\n" "base,hostid"
	awk -F',' 'NR==1{next} NF==2{print $1","$2}' "$ALLOC"
} >"$ALLOC_MERGED"

# Determine next hostid
next_id="$(awk -F',' 'NR>1{if($2>m)m=$2} END{print (m==""?1:m+1)}' "$ALLOC_MERGED")"

# Add any missing bases
awk -F'\t' '{print $4}' "$NORM" | sort -u | while IFS= read -r base; do
	[ -n "$base" ] || continue
	if ! awk -F',' -v b="$base" 'NR>1 && $1==b{found=1} END{exit(found?0:1)}' "$ALLOC_MERGED"; then
		printf "%s,%s\n" "$base" "$next_id" >>"$ALLOC_MERGED"
		next_id=$((next_id + 1))
	fi
done

# TSV view for lookups in the plan loop: base<TAB>hostid
ALLOC_NEW="$STAGE/alloc.new.tsv"
awk -F',' 'NR==1{next} {printf "%s\t%s\n",$1,$2}' "$ALLOC_MERGED" >"$ALLOC_NEW"

# Default DNS label for plan output (you can refine per iface later)
DNS_DEFAULT="127.0.0.1"

# Emit plan.tsv (derived, padded, non-authoritative)
PLAN_TMP="$STAGE/plan.tsv"

{
	cat <<'EOF'
# --------------------------------------------------------------------
# GENERATED FILE — NOT AUTHORITATIVE
#
# This file is a compiled view of WireGuard intent.
# DO NOT EDIT.
#
# Authoritative sources:
#   - /volume1/homelab/wireguard/input/clients.csv
#   - scripts/wg-compile.sh
#
# This file exists for human verification and audit only.
# --------------------------------------------------------------------
EOF

	printf "%-18s %-6s %-8s %-15s %-22s %-22s\n" \
		"base" "iface" "hostid" "dns" "allowed_ips" "endpoint"

	while IFS=$'\t' read -r user machine iface base; do
			[ -n "$base" ] || continue

			case "$iface" in wg[0-7]) : ;; *)
					die "invalid iface '$iface' for base=$base"
			esac

			ifnum="${iface#wg}"
			endpoint="${ENDPOINT_HOST_BASE}:$((ENDPOINT_PORT_BASE + ifnum))"

			hid="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$ALLOC_NEW" | head -n1)"
			[ -n "$hid" ] || die "no hostid for base=$base"

			case "$iface" in
					wg6|wg7)
							allowed="0.0.0.0/0,::/0"
							;;
					*)
							allowed="10.89.12.0/24"
							;;
			esac

			printf "%-18s %-6s %-8s %-15s %-22s %-22s\n" \
					"$base" "$iface" "$hid" "$DNS_DEFAULT" "$allowed" "$endpoint"

done <"$NORM"


} >"$PLAN_TMP"

# Commit compiled outputs atomically
mv -f "$PLAN_TMP" "$PLAN"
chmod 600 "$PLAN"

# (clients.lock.csv and alloc.csv unchanged)
mv -f "$LOCK_TMP" "$LOCK"
chmod 600 "$LOCK"

mv -f "$STAGE/alloc.merged.csv" "$ALLOC"
chmod 600 "$ALLOC"

echo "wg-compile: OK"
echo "  input:    $IN_CSV"
echo "  lock:     $LOCK"
echo "  alloc:    $ALLOC"
echo "  plan:     $PLAN"