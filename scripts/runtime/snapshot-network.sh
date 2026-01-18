#!/usr/bin/env bash
set -euo pipefail
umask 077

OUT="${1:?snapshot dir required}"
[ -d "$OUT" ] || mkdir -p "$OUT"

# WireGuard runtime (canonical, order‑independent)
wg show all dump | sort >"$OUT/wg.dump"

# IP addresses (canonical)
ip -o addr show | sort >"$OUT/ip.addr"

# Routes (canonical)
ip route show table main | sort >"$OUT/route.v4"
ip -6 route show table main | sort >"$OUT/route.v6"
