#!/usr/bin/env bash
# wg-ensure-server-keys.sh
set -eu
umask 077

# shellcheck disable=SC1091
source /usr/local/bin/common.sh

: "${WG_ROOT:?WG_ROOT not set}"

WG_DIR="/etc/wireguard"
PUBDIR="$WG_ROOT/compiled/server-pubkeys"

PLAN="$WG_ROOT/compiled/plan.tsv"
OUT_BASE="$WG_ROOT/out/server/base"

INSTALL_IF_CHANGED="/usr/local/bin/install_if_changed.sh"

[ -x "$INSTALL_IF_CHANGED" ] || {
    echo "wg-ensure-server-keys: ERROR: install_if_changed.sh not found or not executable" >&2
    exit 1
}

[ -f "$PLAN" ] || {
    echo "wg-ensure-server-keys: ERROR: missing $PLAN" >&2
    exit 1
}

mkdir -p "$OUT_BASE"
chmod 700 "$OUT_BASE" 2>/dev/null || true

ifaces="$(
        awk '
                /^#/ { next }
                /^[[:space:]]*$/ { next }

                # New plan.tsv header (current schema)
                $1=="node" && $2=="iface" { next }
                $2=="iface" { next }

                # Old legacy header (keep for backward compatibility)
                $1=="base" && $2=="iface" && $3=="slot" &&
                $4=="dns" && $5=="client_addr4" && $6=="client_addr6" &&
                $7=="AllowedIPs_client" && $8=="AllowedIPs_server" &&
                $9=="endpoint" { next }

                { print $2 }
        ' "$PLAN" | sort -u
)"


[ -n "$ifaces" ] || {
    echo "wg-ensure-server-keys: ERROR: no ifaces found in $PLAN" >&2
    exit 1
}

mkdir -p "$PUBDIR"
chmod 700 "$PUBDIR" 2>/dev/null || true

for iface in $ifaces; do
    case "$iface" in
        wg[0-9]|wg1[0-5]) ;;
        *)
            echo "wg-ensure-server-keys: ERROR: invalid iface '$iface'" >&2
            exit 1
            ;;
    esac

    priv="$WG_DIR/$iface.key"
    pub="$WG_DIR/$iface.pub"

    if [ ! -f "$priv" ] || [ ! -f "$pub" ]; then
        mkdir -p "$WG_DIR"
        umask 077
        wg genkey | tee "$priv" | wg pubkey >"$pub"
        chown root:root "$priv" "$pub" 2>/dev/null || true
        chmod 600 "$priv" 2>/dev/null || true
        chmod 644 "$pub" 2>/dev/null || true
    fi

    # Publish the server pubkey into the compiled artifact directory (renderer contract)
    rc=0
    "$INSTALL_IF_CHANGED" --quiet "$pub" "$PUBDIR/$iface.pub" root root 644 || rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne "$INSTALL_IF_CHANGED_EXIT_CHANGED" ]; then
        exit "$rc"
    fi


    i="${iface#wg}"
    out="$OUT_BASE/$iface.conf"

    # Ensure semantics: never overwrite existing base config
    [ -f "$out" ] && continue

    (
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT

        cat >"$tmp" <<EOF
[Interface]
Address = 10.${i}.0.1/16, fd89:7a3b:42c0:${i}::1/64
ListenPort = $((51420 + i))
PrivateKey = __REPLACED_AT_DEPLOY__
EOF

        case "$iface" in
            wg4|wg7) echo "Table = off" >>"$tmp" ;;
        esac

        "$INSTALL_IF_CHANGED" --quiet "$tmp" "$out" root root 600
    )
done
