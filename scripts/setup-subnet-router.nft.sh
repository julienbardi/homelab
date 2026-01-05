#!/bin/bash
# setup-subnet-router.nft.sh
# Idempotent nft conversion of setup-subnet-router.sh
set -euo pipefail

# Resolve homelab repo root (script lives in scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
export HOMELAB_DIR

CLEANUP_LEGACY=${CLEANUP_LEGACY:-0}

# --- Topology (adjust if needed: probably eth0, eth1 or br0) ---
LAN_IF="eth0"
LAN_SUBNET="10.89.12.0/24"
LAN_SUBNET_V6="2a01:8b81:4800:9c00::/64"
WG_IF_PREFIX="wg"

GLOBAL_IPV6_PREFIX="2a01:8b81:4800:9c00"
GLOBAL_PREFIX_LEN=60 # exactly 16 /64 subnets (1 for LAN and 15 for wireguard) out of the 256 delegated by ISP. 56 is future proof

# WireGuard profile bitmask model (wg1..wg15)
BIT_LAN=0   # LAN access
BIT_V4=1    # Internet IPv4
BIT_V6=2    # Internet IPv6
# BIT_FULL intentionally omitted here: only used in wg-compile for AllowedIPs_client

# Canonical functions (duplicated from wg-compile.sh)
wg_hextet_from_ifnum() {
	n="$1"
	[ "$n" -ge 1 ] && [ "$n" -le 15 ] || {
		log "ERROR: invalid wg interface index '$n' (expected 1..15)"
		exit 1
	}
	printf "9c0%x" "$n"
}

wg_ipv6_subnet_for_ifnum() {
	n="$1"
	hextet="$(wg_hextet_from_ifnum "$n")"
	printf "2a01:8b81:4800:%s::/64" "$hextet"
}


# --- Helper: delete rules in a chain that match a fixed string (by handle) ---
delete_rules_matching_in_chain() {
	local table="$1" chain="$2" needle="$3"

	# List rules with handles, normalize whitespace, and match safely
	nft -a list chain "$table" "$chain" 2>/dev/null \
	| while IFS= read -r line; do
		# Normalize whitespace to avoid AWK crashes and substring mismatches
		norm="$(printf '%s' "$line" | tr -s '[:space:]' ' ')"

		# Skip table/chain headers
		case "$norm" in
			"table "* | "chain "* ) continue ;;
		esac

		# Match only real rules containing the needle
		case "$norm" in
			*"$needle"*)
				# Extract handle safely
				handle="$(printf '%s\n' "$norm" | awk '
					{
						if (match($0, /# handle ([0-9]+)/, m)) {
							print m[1]
						}
					}
				')"

				if [[ -n "$handle" ]]; then
					log "Deleting rule in ${table} ${chain} matching '${needle}' (handle ${handle})"
					nft delete rule "$table" "$chain" handle "$handle" || true
				fi
				;;
		esac
	done
}

cleanup_wg_ipv6_noncanonical_in_chain() {
  local chain="$1" wg_if="$2" canon="$3"
  nft -a list chain inet filter "$chain" 2>/dev/null \
  | tr -s '[:space:]' ' ' \
  | while IFS= read -r line; do
	  case "$line" in
		*"iifname \"${wg_if}\""*ip6*" saddr "*)
		  case "$line" in
			*"ip6 saddr ${canon}"*) : ;;
			*)
			  handle="$(printf '%s\n' "$line" | awk 'match($0,/ # handle ([0-9]+)/,m){print m[1]}')"
			  [ -n "$handle" ] && nft delete rule inet filter "$chain" handle "$handle" || true
			  ;;
		  esac
		  ;;
	  esac
	done
}

cleanup_legacy_rules() {
	log "Running legacy nft cleanup..."

	# 1. Remove any wg0 rules (wg0 is forbidden)
	delete_rules_matching_in_chain inet filter input  'iifname "wg0"'
	delete_rules_matching_in_chain inet filter forward 'iifname "wg0"'
	delete_rules_matching_in_chain inet filter forward 'oifname "wg0"'

	# 2. Remove old /64 NDP proxying
	delete_rules_matching_in_chain inet filter forward '9c00::/64'

	# 3. Remove old overly-broad forward-accept rules
	delete_rules_matching_in_chain inet filter forward 'forward-accept'

	# 4. Remove legacy NAT rules not tied to current LAN_IF
	delete_rules_matching_in_chain ip nat postrouting "oifname \"${LAN_IF}\""

	#delete_rules_matching_in_chain ip nat postrouting 'masquerade'

	# 5. Remove WRONG decimal-based IPv6 subnets for wg10..wg15
	# Correct model uses hex (9c0a..9c0f), not decimal (10..15)
	for i in $(seq 10 15); do
		# Match any rule containing :<decimal>:: which is invalid
		delete_rules_matching_in_chain inet filter input  ":${i}::"
		delete_rules_matching_in_chain inet filter forward ":${i}::"
		delete_rules_matching_in_chain inet filter output ":${i}::"

		# Also clean NAT table just in case
		delete_rules_matching_in_chain ip nat postrouting ":${i}::"
	done

	# 6. Remove any IPv6 rules on wg1..wg15 that do NOT match the canonical subnet
	for i in $(seq 1 15); do
		WG_IF="${WG_IF_PREFIX}${i}"
		CANON_V6="$(wg_ipv6_subnet_for_ifnum "$i")"

		# Delete any IPv6 rule on wgX that does not reference the canonical subnet
		cleanup_wg_ipv6_noncanonical_in_chain input "$WG_IF" "$CANON_V6"
		cleanup_wg_ipv6_noncanonical_in_chain forward "$WG_IF" "$CANON_V6"
	done

	delete_rules_matching_in_chain inet filter input 'udp dport 51420'
	delete_rules_matching_in_chain inet filter input 'udp dport 51420-51427'
	delete_rules_matching_in_chain inet filter forward 'ct state established,related'

	log "Legacy nft cleanup complete."
}

log() { printf '%s %s\n' "$(date -Iseconds)" "$*"; }

dump_rules_snapshot() {
	mkdir -p "${HOMELAB_DIR}/config"

	nft list table inet filter \
	| sed -E 's/ counter packets [0-9]+ bytes [0-9]+//g; s/ # handle [0-9]+//g' \
	> "${HOMELAB_DIR}/config/nft.inet-filter.txt"

	log "nft inet filter snapshot written to ${HOMELAB_DIR}/config/nft.inet-filter.txt"
}

# --- Require root ---
if [[ $EUID -ne 0 ]]; then
	log "ERROR: must run as root"
	exit 1
fi

# --- Interface guard ---
if ! ip link show "${LAN_IF}" | grep -q "state UP"; then
	log "ERROR: Interface ${LAN_IF} not found or not UP, aborting."
	exit 1
fi

if [ "$CLEANUP_LEGACY" -eq 1 ]; then
	cleanup_legacy_rules
else
	log "Legacy cleanup disabled (CLEANUP_LEGACY=0)"
fi

# --- Kernel tuning: IPv4/IPv6 forwarding ---
log "Enabling IPv4/IPv6 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
sysctl -w net.ipv6.conf.default.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf.default.forwarding=1 >/dev/null
sysctl -w net.ipv4.conf."${LAN_IF}".forwarding=1 >/dev/null || true

# --- Ensure inet filter table/chains exist (vendor-safe) ---
log "Ensuring inet filter table and base chains..."
if ! nft list table inet filter >/dev/null 2>&1; then
	nft create table inet filter
fi

# Create chains only if missing; do NOT touch vendor ip/ip6 filter tables
nft create chain inet filter input   '{ type filter hook input priority 0; policy drop; }'   2>/dev/null || true
nft create chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' 2>/dev/null || true
nft create chain inet filter output  '{ type filter hook output priority 0; policy accept; }' 2>/dev/null || true

# Ensure ip nat table/chain exist (without touching vendor rules)
if ! nft list table ip nat >/dev/null 2>&1; then
	nft create table ip nat
fi
nft create chain ip nat postrouting '{ type nat hook postrouting priority 100; policy accept; }' 2>/dev/null || true

# --- Helper to add rule if missing ---
add_rule() {
	local rule="$1"
	local cmd="$2"

	local norm
	norm="$(printf '%s' "$rule" | tr -s '[:space:]' ' ')"

	if nft list ruleset \
	| sed -E 's/ counter packets [0-9]+ bytes [0-9]+//g; s/ # handle [0-9]+//g' \
	| tr -s '[:space:]' ' ' \
	| grep -Fxq "$norm"; then
		log "Already present: $rule"
	else
		log "Adding rule: $rule"
		eval "$cmd"
	fi
}

# --- Conntrack baseline (ESTABLISHED,RELATED) ---
add_rule \
	"ct state related,established accept" \
	"nft add rule inet filter input ct state related,established accept"

add_rule \
	"ct state related,established accept" \
	"nft add rule inet filter forward ct state related,established accept"


# --- LAN host accepts (IPv4 + IPv6) ---
add_rule "iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr ${LAN_SUBNET} accept"
add_rule "iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip6 saddr ${LAN_SUBNET_V6} accept"

# --- Trusted router WireGuard clients (10.6.0.0/24 + fd5e:d23d:70e:111::/64) ---
add_rule "iifname \"${LAN_IF}\" ip saddr 10.6.0.0/24 accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip saddr 10.6.0.0/24 accept"

add_rule "iifname \"${LAN_IF}\" ip6 saddr fd5e:d23d:70e:111::/64 accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" ip6 saddr fd5e:d23d:70e:111::/64 accept"

# --- Essential service ports on host (DNS/SSH/HTTPS/UPnP/SMB/wsdd2/etc.) ---
add_rule \
	"tcp dport 443 accept" \
	"nft add rule inet filter input tcp dport 443 accept"

add_rule "udp dport 53 accept" \
	"nft add rule inet filter input udp dport 53 accept"
add_rule "tcp dport 53 accept" \
	"nft add rule inet filter input tcp dport 53 accept"
add_rule "tcp dport 22 accept" \
	"nft add rule inet filter input tcp dport 22 accept"
add_rule "tcp dport 2222 accept" \
	"nft add rule inet filter input tcp dport 2222 accept"
add_rule "tcp dport 9999 accept" \
	"nft add rule inet filter input tcp dport 9999 accept"
add_rule "tcp dport 9443 accept" \
	"nft add rule inet filter input tcp dport 9443 accept"

# --- Allow Unbound DNS replies (loopback, UDP/TCP source port 5335) ---
add_rule "iifname \"lo\" udp sport 5335 accept" "nft add rule inet filter output iifname \"lo\" udp sport 5335 accept"
add_rule "iifname \"lo\" tcp sport 5335 accept" "nft add rule inet filter output iifname \"lo\" tcp sport 5335 accept"

# --- Allow DNS queries to Unbound (loopback, UDP/TCP source port 5335)---
add_rule "iifname \"lo\" udp dport 5335 accept" "nft add rule inet filter input iifname \"lo\" udp dport 5335 accept"
add_rule "iifname \"lo\" tcp dport 5335 accept" "nft add rule inet filter input iifname \"lo\" tcp dport 5335 accept"


add_rule "tcp dport 445 accept" "nft add rule inet filter input tcp dport 445 accept"  # SMB
add_rule "udp dport 3702 accept" "nft add rule inet filter input udp dport 3702 accept" # wsdd2
add_rule "udp dport 1900 accept" "nft add rule inet filter input udp dport 1900 accept" # UPnP/SSDP

# --- WireGuard handshake ports on LAN uplink ---
# Accept UDP 51420-51435 on LAN_IF (IPv4 + IPv6 via inet table)
add_rule "iifname \"${LAN_IF}\" udp dport 51420-51435 ct state new,established accept" \
	"nft add rule inet filter input iifname \"${LAN_IF}\" udp dport {51420-51435} ct state new,established accept"

# --- Trusted router WireGuard clients -> LAN (IPv4 + IPv6) ---
add_rule \
	"iifname \"${LAN_IF}\" oifname \"${LAN_IF}\" ip saddr 10.6.0.0/24 ip daddr ${LAN_SUBNET} accept" \
	"nft add rule inet filter forward iifname \"${LAN_IF}\" oifname \"${LAN_IF}\" ip saddr 10.6.0.0/24 ip daddr ${LAN_SUBNET} accept"

add_rule \
	"iifname \"${LAN_IF}\" oifname \"${LAN_IF}\" ip6 saddr fd5e:d23d:70e:111::/64 ip6 daddr ${LAN_SUBNET_V6} accept" \
	"nft add rule inet filter forward iifname \"${LAN_IF}\" oifname \"${LAN_IF}\" ip6 saddr fd5e:d23d:70e:111::/64 ip6 daddr ${LAN_SUBNET_V6} accept"

# --- WireGuard per-interface host + forward rules (wg0..wg7) ---
for i in $(seq 1 15); do
	WG_IF="${WG_IF_PREFIX}${i}"

	# Bitmask evaluation (same as wg-compile.sh)
	has_lan=$(( (i >> BIT_LAN) & 1 ))
	has_v4=$(( (i >> BIT_V4) & 1 ))
	has_v6=$(( (i >> BIT_V6) & 1 ))

	#IPV4_SUBNET=$(echo "$WG_IPV4S" | cut -d' ' -f $((i+1)) | sed 's#/24##') # old rule
	IPV4_SUBNET="10.${i}.0.0/16"
	
	#IPV6_SUBNET=$(echo "$WG_IPV6S" | cut -d' ' -f $((i+1)) | sed 's#/128#/64#') # old rule
	IPV6_SUBNET="$(wg_ipv6_subnet_for_ifnum "$i")"

	PORT=$((51420 + i))

	if ip link show "${WG_IF}" >/dev/null 2>&1; then
		log "Configuring ${WG_IF} rules (subnets ${IPV4_SUBNET}, ${IPV6_SUBNET}, port ${PORT})"

		# Host access from wgX (kept broad: allows DoH/SSH/etc to the NAS itself)
		add_rule "iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept" "nft add rule inet filter input iifname \"${WG_IF}\" ip saddr ${IPV4_SUBNET} accept"
		add_rule "iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept" "nft add rule inet filter input iifname \"${WG_IF}\" ip6 saddr ${IPV6_SUBNET} accept"

		# Handshake path on LAN uplink: accept UDP port for this interface (no source restriction)
		add_rule "iifname \"${LAN_IF}\" udp dport ${PORT} accept" \
			"nft add rule inet filter input iifname \"${LAN_IF}\" udp dport ${PORT} ct state new,established accept"

		# --- Bitmask-gated LAN access ---
		# LAN means: can reach LAN_SUBNET + LAN_SUBNET_V6 through LAN_IF
		if [ "$has_lan" -eq 1 ]; then
			# IPv4 LAN
			add_rule \
				"iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} ip daddr ${LAN_SUBNET} accept" \
				"nft add rule inet filter forward iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} ip daddr ${LAN_SUBNET} accept"

			add_rule \
				"iifname \"${LAN_IF}\" oifname \"${WG_IF}\" ip saddr ${LAN_SUBNET} ip daddr ${IPV4_SUBNET} accept" \
				"nft add rule inet filter forward iifname \"${LAN_IF}\" oifname \"${WG_IF}\" ip saddr ${LAN_SUBNET} ip daddr ${IPV4_SUBNET} accept"


			# IPv6 LAN
			add_rule \
				"iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${IPV6_SUBNET} ip6 daddr ${LAN_SUBNET_V6} accept" \
				"nft add rule inet filter forward iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${IPV6_SUBNET} ip6 daddr ${LAN_SUBNET_V6} accept"

			add_rule \
				"iifname \"${LAN_IF}\" oifname \"${WG_IF}\" ip6 saddr ${LAN_SUBNET_V6} ip6 daddr ${IPV6_SUBNET} accept" \
				"nft add rule inet filter forward iifname \"${LAN_IF}\" oifname \"${WG_IF}\" ip6 saddr ${LAN_SUBNET_V6} ip6 daddr ${IPV6_SUBNET} accept"
		else
			log "LAN disabled for ${WG_IF} by bitmask"
		fi

		# --- Bitmask-gated Internet IPv4 ---
		if [ "$has_v4" -eq 1 ]; then
			add_rule \
				"iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} ip daddr != ${LAN_SUBNET} accept" \
				"nft add rule inet filter forward iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} ip daddr != ${LAN_SUBNET} accept"


			add_rule \
				"oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} masquerade" \
				"nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${IPV4_SUBNET} masquerade"
		else
			log "IPv4 Internet disabled for ${WG_IF} by bitmask"
		fi

		# --- Bitmask-gated Internet IPv6 (routed, no NAT66) ---
		if [ "$has_v6" -eq 1 ]; then
			# Allow forwarding out to LAN_IF for non-LAN IPv6 destinations (internet v6)
			add_rule \
				"iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${IPV6_SUBNET} ip6 daddr != ${LAN_SUBNET_V6} accept" \
				"nft add rule inet filter forward iifname \"${WG_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${IPV6_SUBNET} ip6 daddr != ${LAN_SUBNET_V6} accept"

		else
			log "IPv6 Internet disabled for ${WG_IF} by bitmask"
		fi

		log "✅ ${WG_IF} nft rules ensured."
	else
		log "⚠️ ${WG_IF} not present, skipping."
	fi
done

# --- Tailscale rules (if present) ---
TS_IF="tailscale0"
TS_SUBNET_V4="100.64.0.0/10"
TS_SUBNET_V6="fd7a:115c:a1e0::/48"

if ip link show "${TS_IF}" >/dev/null 2>&1; then
	add_rule "iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept" \
		"nft add rule inet filter input iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
	add_rule "iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} forward-accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" ip saddr ${TS_SUBNET_V4} accept"
	add_rule "oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} forward-accept" \
		"nft add rule inet filter forward oifname \"${TS_IF}\" ip daddr ${TS_SUBNET_V4} accept"
	add_rule "oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade" \
		"nft add rule ip nat postrouting oifname \"${LAN_IF}\" ip saddr ${TS_SUBNET_V4} masquerade"

	add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept" \
		"nft add rule inet filter input iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
	add_rule "iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} forward-accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" ip6 saddr ${TS_SUBNET_V6} accept"
	add_rule "oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} forward-accept" \
		"nft add rule inet filter forward oifname \"${TS_IF}\" ip6 daddr ${TS_SUBNET_V6} accept"

	# NEW: Tailscale IPv6 -> LAN IPv6
	add_rule \
		"iifname \"${TS_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${TS_SUBNET_V6} ip6 daddr ${LAN_SUBNET_V6} accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${TS_SUBNET_V6} ip6 daddr ${LAN_SUBNET_V6} accept"

	# NEW: LAN IPv6 -> Tailscale IPv6
	add_rule \
		"iifname \"${LAN_IF}\" oifname \"${TS_IF}\" ip6 saddr ${LAN_SUBNET_V6} ip6 daddr ${TS_SUBNET_V6} accept" \
		"nft add rule inet filter forward iifname \"${LAN_IF}\" oifname \"${TS_IF}\" ip6 saddr ${LAN_SUBNET_V6} ip6 daddr ${TS_SUBNET_V6} accept"


	# NEW: Tailscale IPv6 -> Internet IPv6 (non-LAN)
	add_rule \
		"iifname \"${TS_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${TS_SUBNET_V6} ip6 daddr != ${LAN_SUBNET_V6} accept" \
		"nft add rule inet filter forward iifname \"${TS_IF}\" oifname \"${LAN_IF}\" ip6 saddr ${TS_SUBNET_V6} ip6 daddr != ${LAN_SUBNET_V6} accept"

	log "Tailscale nft rules applied."
else
	log "Tailscale interface ${TS_IF} not found, skipping Tailscale rules."
fi

# --- GRO tuning ---
log "Applying GRO tuning on ${LAN_IF}..."
if ethtool -K "${LAN_IF}" gro off 2>/dev/null; then
	log "GRO disabled on ${LAN_IF}"
else
	log "WARN: Failed to disable GRO on ${LAN_IF}"
fi

# --- Configure NDP proxying (idempotent) ---
log "Ensuring NDP proxying for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN}..."

if ! command -v ndppd >/dev/null 2>&1; then
	log "ERROR: ndppd is not installed. IPv6 routing for WireGuard/Tailscale clients will FAIL."
	log "ERROR: Install ndppd via 'make deps' (install-pkg-ndppd) and re-run this script."
	exit 1
fi

DESIRED_NDPPD_CONF=$(cat <<EOF
route-ttl 300
proxy ${LAN_IF} {
	router yes
	timeout 500
	ttl 300
	rule ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} {
		auto
	}
}
EOF
)

# Write config only if changed
if [ ! -f /etc/ndppd.conf ] || ! diff -q <(printf "%s" "$DESIRED_NDPPD_CONF") /etc/ndppd.conf >/dev/null; then
	log "Updating /etc/ndppd.conf..."
	printf "%s\n" "$DESIRED_NDPPD_CONF" > /etc/ndppd.conf
	ndppd_needs_restart=1
else
	log "/etc/ndppd.conf already up to date."
	ndppd_needs_restart=0
fi

# Enable service if needed
if ! systemctl is-enabled ndppd.service >/dev/null 2>&1; then
	log "Enabling ndppd.service..."
	systemctl enable ndppd.service
fi

# Start or restart service if needed
if ! systemctl is-active ndppd.service >/dev/null 2>&1; then
	log "Starting ndppd.service..."
	systemctl start ndppd.service
elif [ "$ndppd_needs_restart" -eq 1 ]; then
	log "Restarting ndppd.service due to config change..."
	systemctl restart ndppd.service
else
	log "ndppd.service already running with correct config."
fi

# Ensure kernel route for the /64 is present (idempotent)
log "Ensuring kernel route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} on ${LAN_IF}"
ip -6 route replace "${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN}" dev "${LAN_IF}" >/dev/null 2>&1 || true
log "Local route for ${GLOBAL_IPV6_PREFIX}::/${GLOBAL_PREFIX_LEN} ensured."

# --- Persist nft ruleset (without touching vendor tables) ---
log "Persisting nft ruleset to /etc/nftables.conf..."
nft list ruleset > /etc/nftables.conf
log "Subnet router nft configuration complete."

# --- Snapshot inet filter rules for git tracking ---
dump_rules_snapshot
