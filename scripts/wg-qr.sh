#!/usr/bin/env bash
set -euo pipefail
# shellcheck shell=bash
conf="$1"
png="${2:-}"

[ -f "$conf" ] || { echo "ERROR: missing config $conf" >&2; exit 1; }

command -v qrencode >/dev/null || {
    echo "ERROR: qrencode not installed" >&2
    exit 1
}

# Terminal QR
qrencode -t ansiutf8 < "$conf"

# Optional PNG output
if [ -n "$png" ]; then
    qrencode -o "$png" < "$conf"
    echo "QR PNG written to $png"
fi