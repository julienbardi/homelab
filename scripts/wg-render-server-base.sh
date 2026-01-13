#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Render WireGuard server base configs
#
# Inputs:
#   WG_ROOT/compiled/plan.tsv
#   WG_ROOT/compiled/server-pubkeys/
#
# Outputs:
#   WG_ROOT/out/server/base/wgX.conf
#
# Notes:
# - Intent-driven only
# - Does NOT generate or read private keys
# - Safe to re-run
# ------------------------------------------------------------

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="${WG_ROOT}/compiled/plan.tsv"
PUBDIR="${WG_ROOT}/compiled/server-pubkeys"
OUTDIR="${WG_ROOT}/out/server/base"

echo "[wg] Rendering server base configs"
echo "  plan:   ${PLAN}"
echo "  pubs:   ${PUBDIR}"
echo "  output: ${OUTDIR}"

# ------------------------------------------------------------
# Guards
# ------------------------------------------------------------

[ -f "${PLAN}" ]   || { echo "❌ missing plan.tsv"; exit 1; }
[ -d "${PUBDIR}" ] || { echo "❌ missing server pubkey directory"; exit 1; }

mkdir -p "${OUTDIR}"

# ------------------------------------------------------------
# Extract unique interfaces from plan.tsv
# ------------------------------------------------------------

awk -F'\t' '
	/^#/ { next }
	/^[[:space:]]*$/ { next }
	$1=="base" && $2=="iface" { next }
	{ print $2 }
' "${PLAN}" | sort -u | while read -r iface; do
	conf="${OUTDIR}/${iface}.conf"
	pub="${PUBDIR}/${iface}.pub"

	echo "▶ ${iface}"

	[ -f "${pub}" ] || { echo "❌ missing ${pub}"; exit 1; }

	# If base config already exists, do not overwrite private key
	if [ -f "${conf}" ]; then
		echo "  exists ${conf} (preserving private key)"
		continue
	fi

	# Render minimal base config WITHOUT private key
	cat > "${conf}" <<EOF
# --------------------------------------------------
# WireGuard server base config
# Interface: ${iface}
# Generated: $(date -Is)
# --------------------------------------------------

[Interface]
# PrivateKey intentionally omitted (already provisioned)
ListenPort = $(awk -F'\t' -v i="${iface}" '$2==i {print $9; exit}' "${PLAN}")
EOF

	echo "  wrote ${conf}"
done

echo "✅ server base configs rendered"
