#!/usr/bin/env bash
#
# scripts/wg-compile-clients.sh
#
# Deterministic client + server peer generation from authoritative CSV.
# One worker per interface (parallel-safe).
#

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

: "${WG_INPUT_DIR:?WG_INPUT_DIR not set}"
CSV="${WG_INPUT_DIR}/clients.csv"

OUT_CLIENT="${SCRIPT_DIR}/../out/clients"
OUT_SERVER="${SCRIPT_DIR}/../out/server/peers"

WG_DNS4="127.0.0.1"
WG_DNS6="::1"

WG_ENDPOINT_HOST="${WG_ENDPOINT_HOST:-vpn.bardi.ch}"
WG_PORT_BASE="${WG_PORT_BASE:-51420}"

KEY_WIDTH=16

mkdir -p "$OUT_CLIENT" "$OUT_SERVER"

if [ ! -f "$CSV" ]; then
	echo "ERROR: missing clients.csv at $CSV" >&2
	exit 1
fi

compile_iface() {
	local iface="$1"
	local ifnum="${iface#wg}"

	if ! [[ "$ifnum" =~ ^[0-9]+$ ]]; then
		echo "ERROR: invalid iface '$iface'" >&2
		exit 1
	fi

	local server_pub="/etc/wireguard/${iface}.pub"
	if [ ! -f "$server_pub" ]; then
		echo "ERROR: missing server public key $server_pub" >&2
		exit 1
	fi

	local server_pubkey
	server_pubkey="$(tr -d '\r\n' <"$server_pub")"

	local port="$((WG_PORT_BASE + ifnum))"

	echo "compiling interface $iface"

	awk -F',' \
		-v IFACE="$iface" \
		-v IFNUM="$ifnum" \
		-v OUTC="$OUT_CLIENT" \
		-v OUTS="$OUT_SERVER" \
		-v SERVER_PUB="$server_pubkey" \
		-v ENDPOINT="$WG_ENDPOINT_HOST" \
		-v PORT="$port" \
		-v DNS4="$WG_DNS4" \
		-v DNS6="$WG_DNS6" \
		-v KEYW="$KEY_WIDTH" '
		function trim(s) {
			sub(/^[[:space:]]+/, "", s)
			sub(/[[:space:]]+$/, "", s)
			return s
		}

		function kv(file, key, val) {
			printf "%-*s = %s\n", KEYW, key, val >> file
		}

		NR == 1 { next }
		$0 ~ /^[[:space:]]*$/ { next }

		{
			user    = trim($1)
			machine = trim($2)
			iface   = trim($3)

			if (iface != IFACE) next

			client_pub  = trim($4)
			client_priv = trim($5)
			allowed     = trim($6)
			profile     = trim($7)

			if (user == "" || machine == "" || client_pub == "" || client_priv == "") next

			idx++

			# IPv4 tunnel address
			ipv4 = sprintf("10.4.%d.%d", IFNUM, 10 + idx)
			addr4 = ipv4 "/32"

			# IPv6 tunnel address (single ::, deterministic)
			ipv6 = sprintf("2a01:8b81:4800:9c00:%d::%d", IFNUM, 10 + idx)
			addr6 = ipv6 "/128"

			ts = strftime("%Y-%m-%dT%H:%M:%SZ", systime())

			base = user "-" machine "-" iface

			client_file = OUTC "/" base ".conf"
			server_file = OUTS "/" iface "/" user "-" machine ".conf"

			# ---- client config ----
			print "# " base                          >  client_file
			print "# Interface: " iface              >> client_file
			print "# Profile: " profile              >> client_file
			print "# Generated: " ts                 >> client_file
			print ""                                 >> client_file
			print "[Interface]"                      >> client_file
			kv(client_file, "PrivateKey", client_priv)
			kv(client_file, "Address", addr4 ", " addr6)
			kv(client_file, "DNS", DNS4 ", " DNS6)
			print ""                                 >> client_file
			print "[Peer]"                           >> client_file
			print "# Server: homelab-" iface         >> client_file
			kv(client_file, "PublicKey", SERVER_PUB)
			kv(client_file, "Endpoint", ENDPOINT ":" PORT)
			kv(client_file, "AllowedIPs", allowed "   # Client: What traffic should I send into the tunnel?")
			kv(client_file, "PersistentKeepalive", "25")
			close(client_file)

			# ---- server peer fragment ----
			print "# " base                          >  server_file
			print "# Interface: " iface              >> server_file
			print "# Profile: " profile              >> server_file
			print "# Generated: " ts                 >> server_file
			print ""                                 >> server_file
			print "[Peer]"                           >> server_file
			print "# " base                          >> server_file
			kv(server_file, "PublicKey", client_pub)
			kv(server_file, "AllowedIPs", addr4 ", " addr6 "   # Server: What IPs am I willing to route to this peer?")
			close(server_file)
		}
	' "$CSV"
}

mapfile -t IFACES < <(
	awk -F',' 'NR>1 {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); if ($3!="") print $3}' "$CSV" | sort -u
)

if [ "${#IFACES[@]}" -eq 0 ]; then
	echo "ERROR: no interfaces found in clients.csv" >&2
	exit 1
fi

pids=()
for iface in "${IFACES[@]}"; do
	compile_iface "$iface" &
	pids+=( "$!" )
done

for pid in "${pids[@]}"; do
	wait "$pid"
done

echo "client configs written to $OUT_CLIENT"
echo "server peer fragments written to $OUT_SERVER"
