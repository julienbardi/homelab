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

# --- [unchanged normalization + allocation logic above] ---

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

  while IFS= read -r base; do
    [ -n "$base" ] || continue

    ifnum="${iface#wg}"
    endpoint="${ENDPOINT_HOST_BASE}:$((ENDPOINT_PORT_BASE + ifnum))"

    hid="$(awk -F'\t' -v b="$base" '$1==b{print $2}' "$ALLOC_NEW" | head -n1)"
    iface="$(awk -F'\t' -v b="$base" '$4==b{print $3}' "$NORM" | head -n1)"

    case "$iface" in
      wg6|wg7)
        allowed="0.0.0.0/0,::/0"
        ;;
      *)
        allowed="192.168.50.0/24"
        ;;
    esac

    printf "%-18s %-6s %-8s %-15s %-22s %-22s\n" \
      "$base" "$iface" "$hid" "$DNS_DEFAULT" "$allowed" "$endpoint"

  done <"$BASES"

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