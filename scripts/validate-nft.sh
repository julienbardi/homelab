#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# homelab-firewall-safety-checks.sh
#
# PURPOSE:
#   Validates the homelab nftables ruleset (scripts/homelab.nft) against
#   NetBird, Tailscale, and WireGuard bit‑model safety constraints.
#
#   This script performs static pattern checks to ensure the firewall does not
#   interfere with overlay networks, routing semantics, NAT boundaries, or
#   conntrack behavior required by:
#     - NetBird (wt0, marks, raw hooks, NAT ranges)
#     - Tailscale (tailscale0 isolation, NAT, PMTUD, MSS clamp)
#     - WireGuard (wgX interface isolation, NAT ranges, reject rules)
#
# CONTRACT:
#   - Never mutates system state.
#   - Reads only scripts/homelab.nft.
#   - Exits non‑zero on safety violations.
#   - Output is operator‑grade and machine‑parsable.
#
# NOTES:
#   - This is a *static* validator: it does not parse nft syntax trees.
#   - It is safe to run during CI, converge-network, or pre‑apply checks.
# ------------------------------------------------------------------------------
set -euo pipefail

echo "[homelab-firewall] Running NetBird/Tailscale/WG safety checks..."

NFT_FILES="scripts/homelab.nft"

if [ ! -f "$NFT_FILES" ]; then
    echo "[homelab-firewall] scripts/homelab.nft not found — skipping checks."
    exit 0
fi

FAIL=0

# Prepare a temp file with comments removed
TMP=$(mktemp)
grep -v '^[[:space:]]*#' "$NFT_FILES" > "$TMP"

check() {
    local pattern="$1"
    local message="$2"

    if grep -R -n "$pattern" "$TMP" >/dev/null 2>&1; then
        echo "❌ SAFETY VIOLATION: $message"
        FAIL=1
    fi
}

###############################################################################
# NetBird Safety Checks
###############################################################################

check "\bflush ruleset\b" "# flush ruleset is forbidden — breaks NetBird."
check "\btable ip netbird\b" "# redefining table ip netbird is forbidden."
check "\btable ip6 netbird\b" "# redefining table ip6 netbird is forbidden."
check "\bwt0\b" "# referencing wt0 is forbidden — NetBird interface must not be touched."

# Priority < 100 (match exact numbers)
check "hook input priority [0-9]\{1,2\}\b" "# filter hook priority must be >= 100."
check "hook forward priority [0-9]\{1,2\}\b" "# forward hook priority must be >= 100."
check "hook output priority [0-9]\{1,2\}\b" "# output hook priority must be >= 100."
check "hook postrouting priority [0-9]\{1,2\}\b" "# NAT postrouting priority must be >= 100."

check "\bpolicy drop\b" "# policy drop is forbidden — must use policy accept."

check "\b100\.74\." "# NAT on NetBird IPv4 ranges is forbidden."
check "\bfde2:a01d:6131:bd97\b" "# NAT on NetBird IPv6 ranges is forbidden."

check "\bmeta mark\b" "# meta mark is forbidden — NetBird uses marks."
check "\bct mark\b" "# ct mark is forbidden — NetBird uses marks."
check "\bnotrack\b" "# notrack is forbidden — breaks NetBird conntrack."
check "\bpriority raw\b" "# raw hooks are forbidden — NetBird uses raw hooks."

###############################################################################
# Tailscale Safety Checks
###############################################################################

check "iifname \"tailscale0\".*wt0" "# tailscale0 must not interact with wt0."

# NAT must not target tailscale0 (only NAT rules)
check "^.*oifname \"tailscale0\".*masquerade" "# NAT must not target tailscale0."

check "iifname \"tailscale0\".*maxseg" "# MSS clamp must not apply to tailscale0."
check "iifname \"tailscale0\".*icmp" "# PMTUD must not apply to tailscale0."

###############################################################################
# WireGuard Bit‑Model Safety Checks
###############################################################################

check "wg[0-9].*wt0" "# WG must not interact with wt0."
check "wg[0-9].*tailscale0" "# WG must not interact with tailscale0."

# WG NAT must use /16 ranges only (LAN NAT /24 is allowed)
check "^.*oifname \"eth0\" ip saddr 10\.[0-9]\{1,2\}\.0\.0/24.*masquerade" "# WG NAT must use /16 ranges only."

# WG NAT66 must not touch Tailscale IPv6 (forwarding is allowed)
check "^.*oifname \"eth0\" ip6 saddr fd7a:115c:a1e0.*masquerade" "# WG NAT66 must not touch Tailscale IPv6."

check "\bfde2:a01d:6131:bd97\b" "# WG NAT66 must not touch NetBird IPv6."

check "reject.*iifname \"eth0\"" "# WG reject rules must not target eth0."

###############################################################################
# Final verdict
###############################################################################

rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
    echo "❌ Firewall validation failed"
    exit 1
fi

echo "🟢 Firewall validation passed"
exit 0
