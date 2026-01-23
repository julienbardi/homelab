#!/usr/bin/env bash
set -euo pipefail
umask 077

# ------------------------------------------------------------
# Render WireGuard server base configs
# ------------------------------------------------------------

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="${WG_ROOT}/compiled/plan.tsv"
PUBDIR="${WG_ROOT}/compiled/server-pubkeys"
OUTDIR="${WG_ROOT}/out/server/base"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_IF_CHANGED="${SCRIPT_DIR}/install_if_changed.sh"

[ -x "${INSTALL_IF_CHANGED}" ] || {
	echo "wg-render-server-base: ERROR: install_if_changed.sh not found or not executable" >&2
	exit 1
}

echo "🧱 Rendering server base configs"
echo "  📄 plan:   ${PLAN}"
echo "  🔑 pubs:   ${PUBDIR}"
echo "  📦 output: ${OUTDIR}"

# ------------------------------------------------------------
# Guards
# ------------------------------------------------------------

[ -f "${PLAN}" ]   || { echo "❌ missing plan.tsv"; exit 1; }
[ -d "${PUBDIR}" ] || { echo "❌ missing server pubkey directory"; exit 1; }

mkdir -p "${OUTDIR}"

while read -r iface; do
	conf="${OUTDIR}/${iface}.conf"
	pub="${PUBDIR}/${iface}.pub"

	[ -f "${pub}" ] || { echo "❌ missing ${pub}"; exit 1; }

	tmp="$(mktemp)"
	trap 'rm -f "$tmp"' EXIT

	cat >"$tmp" <<EOF
# --------------------------------------------------
# WireGuard server base config
# Interface: ${iface}
# Generated: $(date -Is)
# --------------------------------------------------

[Interface]
PrivateKey = __REPLACED_AT_DEPLOY__
ListenPort = $(awk -F'\t' -v i="${iface}" '$2==i {print $3; exit}' "${PLAN}")
EOF

	rc=0
	CHANGED_EXIT_CODE=3 \
	"$INSTALL_IF_CHANGED" --quiet "$tmp" "$conf" root root 600 || rc="$?"

	if [ "$rc" -eq 3 ]; then
		echo "🟢 wrote ${conf}"
	elif [ "$rc" -ne 0 ]; then
		exit "$rc"
	fi
done < <(
	awk -F'\t' '
		/^#/ { next }
		/^[[:space:]]*$/ { next }
		$1=="base" && $2=="iface" { next }
		{ print $2 }
	' "${PLAN}" | sort -u
)
