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

# ------------------------------------------------------------
# Extract server_addr4 / server_addr6 for each iface
# ------------------------------------------------------------

while read -r iface; do
    conf="${OUTDIR}/${iface}.conf"
    pub="${PUBDIR}/${iface}.pub"

    [ -f "${pub}" ] || { echo "❌ missing ${pub}"; exit 1; }

    # Extract server_addr4 + server_addr6 from plan.tsv
    read -r server_addr4 server_addr6 < <(
        awk -F'\t' -v i="${iface}" '
            /^#/ || /^[[:space:]]*$/ { next }

            # Header row (v2 schema)
            $1=="node" && $2=="iface" {
                for (n=1; n<=NF; n++) {
                    if ($n=="server_addr4") c4=n
                    if ($n=="server_addr6") c6=n
                }
                if (!c4 || !c6) {
                    print "wg-render-server-base: missing server_addr4/server_addr6 in header" > "/dev/stderr"
                    exit 11
                }
                next
            }

            # Data row
            $2==i { print $(c4), $(c6); exit 0 }
        ' "${PLAN}"
    )

    [ -n "${server_addr4}" ] || { echo "❌ missing server_addr4 for ${iface}"; exit 1; }
    [ -n "${server_addr6}" ] || { echo "❌ missing server_addr6 for ${iface}"; exit 1; }

    printf '%s\n' "$server_addr4" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' \
        || { echo "❌ ${iface}: invalid server_addr4 '${server_addr4}'"; exit 1; }

    printf '%s\n' "$server_addr6" | grep -qE '^[0-9a-f:]+/[0-9]+$' \
        || { echo "❌ ${iface}: invalid server_addr6 '${server_addr6}'"; exit 1; }

    tmp="$(mktemp)"

    if [[ ! "${iface}" =~ ^wg([0-9]|1[0-5])$ ]]; then
        echo "wg-render-server-base: ERROR: invalid iface '${iface}'" >&2
        exit 1
    fi

    # ListenPort convention: 51420 + iface index (wgN)
    listen_port=$((51420 + ${iface#wg}))

    cat >"$tmp" <<EOF
# --------------------------------------------------
# WireGuard server base config
# Interface: ${iface}
# Generated: $(date -Is)
# --------------------------------------------------

[Interface]
PrivateKey = __REPLACED_AT_DEPLOY__
ListenPort = ${listen_port}
Address = ${server_addr4}, ${server_addr6}
EOF

    rc=0
    CHANGED_EXIT_CODE=3 \
    "$INSTALL_IF_CHANGED" --quiet "$tmp" "$conf" root root 600 || rc="$?"

    if [ "$rc" -ne 0 ] && [ "$rc" -ne 3 ]; then
        rm -f "$tmp"
        exit "$rc"
    fi
    rm -f "$tmp"

done < <(
    awk -F'\t' '
        /^#/ { next }
        /^[[:space:]]*$/ { next }

        # Skip header (v2)
        $1=="node" && $2=="iface" { next }

        # Skip legacy header
        $1=="base" && $2=="iface" { next }

        { print $2 }
    ' "${PLAN}" | sort -u
)
