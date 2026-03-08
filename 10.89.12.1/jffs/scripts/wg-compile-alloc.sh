#!/bin/sh
set -eu

IN_PLAN="plan.tsv"
OUT_ALLOC="alloc.tsv"
: "${WG_DUMP:=0}"

[ -f "$IN_PLAN" ] || {
	echo "❌ Missing input file: $IN_PLAN" >&2
	exit 1
}

busybox awk -F'\t' '
NR == 1 {
	if ($0 != "base\tiface\tserver\tvpn4_cidr\tvpn6_cidr") {
		print "❌ Invalid header in plan.tsv" > "/dev/stderr"
		print "   got: [" $0 "]" > "/dev/stderr"
		exit 1
	}
	next
}

{
	base   = $1
	iface  = $2
	server = $3
	v4     = $4
	v6     = $5

	key = base "\t" iface

	# Remember server-backed interfaces
	if (server != "") {
		is_server[key] = 1
	}

	if (!(key in idx)) {
		idx[key] = ++count[iface]
	}

	vpn4[key] = v4
	vpn6[key] = v6

	# Client allocations only (never for server interfaces)
	if (v4 != "" && !(key in is_server)) {
		split(v4, a, "/")
		addr = a[1]
		sub(/\.[0-9]+$/, "." (idx[key] + 1), addr)
		rows[++n] = base "\t" iface "\t" addr "\t" v4
	}

	if (v6 != "" && !(key in is_server)) {
		split(v6, a, "/")
		addr = a[1]
		sub(/::.*$/, "::" (idx[key] + 1), addr)
		rows[++n] = base "\t" iface "\t" addr "\t" v6
	}
}

END {
	print "base\tiface\taddr\tcidr"

	# Emit normal client allocations
	for (i = 1; i <= n; i++) {
		print rows[i]
	}

	# Emit exactly one self-allocation per server interface (prefer v4, else v6)
	for (k in is_server) {
		split(k, a, "\t")
		base  = a[1]
		iface = a[2]

		v4 = vpn4[k]
		v6 = vpn6[k]

		if (v4 != "") {
			split(v4, a, "/")
			addr = a[1]
			print base "\t" iface "\t" addr "\t" addr "/32"
		} else if (v6 != "") {
			split(v6, a, "/")
			addr = a[1]
			print base "\t" iface "\t" addr "\t" addr "/128"
		}
	}
}
' "$IN_PLAN" >"$OUT_ALLOC"

[ "$WG_DUMP" -eq 1 ] && echo "✅ Generated $OUT_ALLOC"
