#!/usr/bin/env bash
set -euo pipefail

# --- Authoritative Context ---
: "${ROUTER_HOST:?Missing ROUTER_HOST}"
: "${ROUTER_SSH_PORT:?Missing ROUTER_SSH_PORT}"
: "${ROUTER_WG_DIR:?Missing ROUTER_WG_DIR}"
: "${WG_ROOT:?Missing WG_ROOT}"
: "${ROUTER_IDENTITY:?Missing ROUTER_IDENTITY}"

# Local paths for NAS/Server execution
NAS_WG_CONF="/etc/wireguard"
INSTALL_FILE_IF_CHANGED="/usr/local/bin/install_file_if_changed_v3.sh"
PEER_MAP="${WG_ROOT}/output/peer-map.tsv"

# Swapped to match Makefile: wgctl.sh [TARGET] [MODE]
TARGET="${1:-}"
MODE="${2:-status}"

# Improved Log function with fixed-width device tags and icons
log() {
	local icon="⚙️"
	case "$MODE" in
		install) icon="📦" ;;
		up)      icon="🚀" ;;
		down)    icon="🛑" ;;
		status)  icon="📊" ;;
	esac

	# Aligns [nas   ] and [router] perfectly
	local tag
	[[ "$TARGET" == "nas" ]] && tag="nas   " || tag="router"

	echo "$icon [$tag] $1"
}

# --- Actions ---

do_install() {
	if [[ "$TARGET" == "router" ]]; then
		# Deployment from NAS output -> Router JFFS
		for conf in "${WG_ROOT}/output/router"/*.conf; do
			[[ -e "$conf" ]] || continue
			"$INSTALL_FILE_IF_CHANGED" -q "" "22" "$conf" \
					   "$ROUTER_HOST" "$ROUTER_SSH_PORT" "${ROUTER_WG_DIR}/$(basename "$conf")" \
					   "0" "0" "0600"
		done
	elif [[ "$TARGET" == "nas" ]]; then
		# Deployment from NAS output -> NAS /etc/wireguard
		for conf in "${WG_ROOT}/output/server"/*.conf; do
			[[ -e "$conf" ]] || continue
			"$INSTALL_FILE_IF_CHANGED" -q "" "22" "$conf" \
					   "" "22" "${NAS_WG_CONF}/$(basename "$conf")" \
					   "0" "0" "0600"
		done
	fi
}

do_up() {
	log "🔌 Bringing up interfaces..."
	if [[ "$TARGET" == "router" ]]; then
		# Ensure eth0 exists
		if [[ ! -d /sys/class/net/eth0 ]]; then
			log "❌ eth0 does not exist — cannot determine NAS link-local IPv6"
			exit 1
		fi

		# Discover NAS link-local IPv6 on eth0
		NAS_LL6="$(ip -6 addr show dev eth0 | awk '/scope link/ {print $2; exit}' | cut -d/ -f1)"

		if [[ -z "$NAS_LL6" || ! "$NAS_LL6" =~ ^fe80: ]]; then
			log "❌ Could not determine valid NAS link-local IPv6 on eth0"
			exit 1
		fi

		log "Using NAS link-local IPv6: ${NAS_LL6}"

		ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" "
			# 🔧 FIX 1: Enable strict error handling (fail fast on any command error)
			set -euo pipefail

			# 🔧 FIX 2: Ensure WireGuard kernel module is loaded before creating interface
			# modprobe returns 0 if already loaded, so this is idempotent
			echo '📦 Ensuring WireGuard kernel module...'
			modprobe wireguard || { echo '❌ Failed to load wireguard module'; exit 1; }

			# Ensure WireGuard interface exists (idempotent)
			if ! ip link show wgs1 >/dev/null 2>&1; then
				echo '🔌 Creating wgs1 interface...'
				ip link add wgs1 type wireguard
			fi

			# Bring interface up before applying config
			echo 'Bringing wgs1 up'
			ip link set wgs1 up

			# Apply WireGuard config
			echo '🔧 Applying WireGuard configuration'
			wg setconf wgs1 ${ROUTER_WG_DIR}/wgs1.conf

			# Assign IPv4 server address
			ip addr add 10.89.101.1/24 dev wgs1 2>/dev/null || true

			# IPv6: router cannot host WG v6, but must route NAS wg7 ULA back to NAS
			ip -6 route del fd89:7a3b:42c0:7::/64 2>/dev/null || true
			ip -6 route replace fd89:7a3b:42c0:7::/64 via ${NAS_LL6} dev eth0
		"
	else
		for f in "${NAS_WG_CONF}"/*.conf; do
			[[ -e "$f" ]] || continue
			sudo wg-quick up "$f" 2>/dev/null || true
		done
	fi
}

do_down() {
	log "Tearing down interfaces..."
	if [[ "$TARGET" == "router" ]]; then
		# wgs1 was brought up manually (ip link add + wg setconf), not via wg-quick.
		# wg-quick down requires a matching wg-quick up state and will silently fail here.
		# Tear down correctly: flush peers, remove addresses, set link down, delete interface.
		ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST" '
			if ip link show wgs1 >/dev/null 2>&1; then
				ip addr flush dev wgs1 2>/dev/null || true
				ip link set down dev wgs1 2>/dev/null || true
				ip link del wgs1 2>/dev/null || true
			fi
		'
	else
		for f in "${NAS_WG_CONF}"/*.conf; do
			[[ -e "$f" ]] || continue
			sudo wg-quick down "$f" 2>/dev/null || true
		done
	fi
}

do_status() {
	local wg_bin="wg"
	local -a remote_cmd
	local now
	now=$(date +%s)

	# Clean early guard for the TSV source of truth
	if [[ ! -f "$PEER_MAP" ]]; then
		PEER_MAP="/root/src/homelab/wireguard/output/peer-map.tsv"
	fi
	if [[ ! -f "$PEER_MAP" ]]; then
		log "❌ peer-map.tsv missing from repository and fallback directory. Status inquiry aborted." >&2
		return 0
	fi

	if [[ "$TARGET" == "router" ]]; then
		remote_cmd=(ssh -i "$ROUTER_IDENTITY" -p "$ROUTER_SSH_PORT" "$ROUTER_HOST")
	else
		remote_cmd=(sudo)
	fi

	# One-shot command processing
	local all_handshakes active_ifaces
	all_handshakes=$("${remote_cmd[@]}" "$wg_bin" show all latest-handshakes 2>/dev/null || echo "")
	active_ifaces=$("${remote_cmd[@]}" "$wg_bin" show interfaces 2>/dev/null || echo "")

	# Single-pass length token calculation
	local max_peer_len
	max_peer_len=$(awk -F'\t' 'NR>1 {l=length($2); if (l>m) m=l} END{print (m>0?m:0)}' "$PEER_MAP")
	((max_peer_len < 12)) && max_peer_len=12

	# Header
	printf "• %-*s  %-5s %-15s %-26s %-14s %-3s\n" \
		"$max_peer_len" "PEER NAME" "IF" "VPN IPv4" "VPN IPv6" "ACCESS" "LAN"

	printf "%0.s-" $(seq 1 $((max_peer_len + 80)))
	echo

	# Rows
	while IFS=$'\t' read -r pk nm iface v4 v6 acc lan || [[ -n "${pk:-}" ]]; do
		[[ -z "${pk:-}" || "$pk" == "pubkey" || "$pk" == "#"* ]] && continue

		# Pure POSIX-safe built-in pattern matching to avoid collision bugs (e.g. wg1 vs wg10)
		case " $active_ifaces " in
			*" $iface "*) ;;
			*) continue ;;
		esac

		local handshake
		handshake=$(printf '%s\n' "$all_handshakes" \
			| awk -v k="$pk" '$1==k {print $3; exit}' 2>/dev/null || echo "0")
		[[ -z "$handshake" ]] && handshake=0

		local icon="○"
		if [[ "$handshake" -gt 0 ]]; then
			if (( now - handshake < 150 )); then
				icon="●"
			else
				icon="◌"
			fi
		fi

		local disp_v4="${v4%/*}"
		local disp_v6="${v6%/*}"

		printf "%s %-*s  %-5s %-15s %-26s %-14s %-3s\n" "$icon" \
			"$max_peer_len" "$nm" "$iface" "$disp_v4" "$disp_v6" "$acc" "$lan"
	done < "$PEER_MAP"
}

# --- Guard & Execute ---
[[ -z "$TARGET" ]] && { echo "Usage: $0 {nas|router} {install|up|down|status}"; exit 1; }

case "$MODE" in
	install)    do_install ;;
	up)         do_up ;;
	down)       do_down ;;
	status)     do_status ;;
	install-up) do_install; do_up ;;
	*)          echo "❌ Unknown mode: $MODE for target: $TARGET"; exit 1 ;;
esac
