#!/usr/bin/env bash
# wg-plan-subnets.sh
set -euo pipefail

WG_ROOT="${WG_ROOT:?WG_ROOT not set}"
IFACES_TSV="${WG_ROOT}/input/wg-interfaces.tsv"

usage() {
  cat <<EOF
Usage: WG_ROOT=/volume1/homelab/wireguard wg-plan-subnets.sh [--router|--nas|--all] [--v4|--v6]

  --router   Only router-hosted interfaces (host_id == "router")
  --nas      Only nas-hosted interfaces (host_id == "nas")
  --all      All interfaces (default)

  --v4       Print IPv4 subnets only
  --v6       Print IPv6 subnets only

Output format (one per line):
  iface<TAB>subnet
EOF
}

scope="all"
family=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --router) scope="router" ;;
    --nas)    scope="nas" ;;
    --all)    scope="all" ;;
    --v4)     family="v4" ;;
    --v6)     family="v6" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ ! -f "$IFACES_TSV" ]]; then
  echo "wg-plan-subnets: missing $IFACES_TSV" >&2
  exit 1
fi

awk -F'\t' -v scope="$scope" -v family="$family" '
  /^#/ { next }
  NF < 7 { next }
  $1 == "iface" { next }

  {
    iface = $1
    host  = $2
    v4    = $5
    v6    = $6
  }

  scope == "router" && host != "router" { next }
  scope == "nas"    && host != "nas"    { next }

  family == "v4" {
    sub(/\/[0-9]+$/, "", v4); # strip prefix length for safety if needed
    print iface "\t" v4
    next
  }

  family == "v6" {
    sub(/\/[0-9]+$/, "", v6)
    print iface "\t" v6
    next
  }

  # default: both
  {
    print iface "\t" v4 "\t" v6
  }
' "$IFACES_TSV"
