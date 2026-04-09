#!/bin/sh
set -eu

IN_DOMAIN="domain.tsv"
OUT_PLAN="plan.tsv"
: "${WG_DUMP:=0}"

[ -f "$IN_DOMAIN" ] || {
	echo "❌ Missing input file: $IN_DOMAIN" >&2
	exit 1
}

busybox awk -F'\t' '
NR == 1 {
	# Strict structural contract: domain → plan
	if ($0 != "base\tiface\tlan\twan\tserver\tvpn4_cidr\tvpn6_cidr") {
		print "❌ Invalid header in domain.tsv" > "/dev/stderr"
		print "   got: [" $0 "]" > "/dev/stderr"
		exit 1
	}

	# Emit plan header
	print "base\tiface\tserver\tvpn4_cidr\tvpn6_cidr"
	next
}

{
	base   = $1
	iface  = $2
	server = $5
	vpn4   = $6
	vpn6   = $7

	print base "\t" iface "\t" server "\t" vpn4 "\t" vpn6
}
' "$IN_DOMAIN" >"$OUT_PLAN"


[ "$WG_DUMP" -eq 1 ] && echo "🛠️ built $OUT_PLAN"
