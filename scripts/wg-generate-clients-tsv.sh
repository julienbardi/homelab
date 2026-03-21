#!/bin/sh
# wg-generate-clients-tsv.sh
set -eu

OUT="/volume1/homelab/wireguard/input/clients.tsv"
DIR="$(dirname "$OUT")"
TMP="$DIR/.clients.tsv.tmp.$$"

# Ensure directory exists before writing temp file
mkdir -p "$DIR"

# Generate into temp file using a single redirect

# WireGuard client table (TSV authority)
# Columns:
#   name, device, os, iface, access, tunnel_mode, lan, v4, v6, dns_v4, dns_v6, notes
#
# Pretty-print:
#   sudo column -t -s $'\t' /volume1/homelab/wireguard/input/clients.tsv | less -S
#
# Notes:
# - This file uses REAL tab characters between fields.
# - Comments appear ABOVE the header row so they do not pollute the table.
# - This script is the authoritative generator; edit here, not the TSV.
{
	# Header
	printf "name\tdevice\tos\tiface\taccess\ttunnel_mode\tlan\tv4\tv6\tdns_v4\tdns_v6\tnotes\n"
	# Rows
	printf "julie-s22\tphone\tandroid\twg7\tfull\tfull\t1\t1\t1\t10.89.12.4,10.89.12.1\tfd89:7a3b:42c0::4\tjulies phone\n"
	printf "julie-acer\tlaptop\twindows\twg7\tfull\tfull\t1\t1\t1\t10.89.12.4,10.89.12.1\tfd89:7a3b:42c0::4\tpersonal laptop\n"
	printf "julie-omen30l\tdesktop\twindows\twg7\tfull\tfull\t1\t1\t1\t10.89.12.4,10.89.12.1\tfd89:7a3b:42c0::4\tworkstation\n"
	printf "sandro-windows\tlaptop\twindows\twg7\tinternet-only\tfull\t0\t1\t1\t10.89.12.4,10.89.12.1\tfd89:7a3b:42c0::4\tfriend device\n"
	printf "sandro-android\tphone\tandroid\twg7\tinternet-only\tfull\t0\t1\t1\t10.89.12.4,10.89.12.1\tfd89:7a3b:42c0::4\tfriend device\n"

} > "$TMP"

# If unchanged → delete temp and exit cleanly
if [ -f "$OUT" ] && cmp -s "$TMP" "$OUT"; then
	rm -f "$TMP"
	echo "🔐 Unchanged $OUT"
	exit 0
fi

# Replace atomically while preserving permissions
install -m 664 -o root -g admin "$TMP" "$OUT"
rm -f "$TMP"

echo "🔐 Updated $OUT"
