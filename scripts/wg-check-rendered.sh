#!/usr/bin/env bash
# wg-check-rendered.sh
set -euo pipefail
IFS=$'\n\t'

: "${WG_ROOT:?WG_ROOT not set}"

PLAN="$WG_ROOT/compiled/plan.tsv"
OUT="$WG_ROOT/out"

die() { echo "❌ wg-check-rendered: $*" >&2; exit 1; }

[ -f "$PLAN" ] || die "missing plan.tsv"
[ -d "$OUT/clients" ] || die "missing out/clients"
[ -d "$OUT/server/base" ] || die "missing out/server/base"
[ -d "$OUT/server/peers" ] || die "missing out/server/peers"

# --------------------------------------------------------------------
# Load plan into associative maps
# --------------------------------------------------------------------

declare -A PLAN

while IFS=$'\t' read -r \
    node iface profile tunnel_mode lan_access egress_v4 egress_v6 \
    c4 c6 ca4 ca6 s4 s6 sa4 sa6 dns endpoint port host_kind
do
    key="$node|$iface"
    PLAN["$key.client_addr"]="$c4,$c6"
    PLAN["$key.client_allowed"]="$ca4,$ca6"
    PLAN["$key.server_addr"]="$s4,$s6"
    PLAN["$key.server_allowed"]="$sa4,$sa6"
    PLAN["$key.dns"]="$dns"
    PLAN["$key.tunnel"]="$tunnel_mode"
    PLAN["$key.lan"]="$lan_access"
done < <(
    awk -F'\t' '
        /^#/ || /^[[:space:]]*$/ { next }
        $1=="node" && $2=="iface" { next }
        { print }
    ' "$PLAN"
)

# --------------------------------------------------------------------
# Client config validation
# --------------------------------------------------------------------

for conf in "$OUT/clients/"*.conf; do
    base_iface="$(basename "$conf" .conf)"
    base="${base_iface%-wg*}"
    iface="${base_iface##*-}"

    key="$base|$iface"
    [ -n "${PLAN[$key.client_addr]:-}" ] || die "unexpected client config $conf"

    addr="$(awk -F' = ' '/^Address/{print $2}' "$conf")"
    [ "$addr" = "${PLAN[$key.client_addr]}" ] \
        || die "$conf: Address mismatch"

    allowed="$(awk -F' = ' '/^AllowedIPs/{print $2}' "$conf")"
    for ip in ${allowed//,/ }; do
        grep -Fq "$ip" <<<"${PLAN[$key.client_allowed]}" \
            || die "$conf: illegal AllowedIP $ip"
    done

    dns="$(awk -F' = ' '/^DNS/{print $2}' "$conf" || true)"
    if [ -n "$dns" ]; then
        for d in ${dns//,/ }; do
            case "$d" in
                10.89.12.4|fd89:7a3b:42c0::4) ;;
                *) die "$conf: illegal DNS $d" ;;
            esac
        done
    fi

    if grep -q '0.0.0.0/0' <<<"$allowed"; then
        [ "${PLAN[$key.tunnel]}" = "full" ] \
            || die "$conf: full tunnel without intent"
    fi

    if grep -Eq '(^|,)2[0-9a-f]{3}:' <<<"$allowed"; then
        die "$conf: global IPv6 route detected"
    fi
done

# --------------------------------------------------------------------
# Server base config validation
# --------------------------------------------------------------------

for conf in "$OUT/server/base/"wg*.conf; do
    iface="$(basename "$conf" .conf)"
    ifnum="${iface#wg}"

    addr="$(awk -F' = ' '/^Address/{print $2}' "$conf")"
    expected="$(awk -F'\t' -v i="$iface" '
        /^#/||$1=="node"{next}
        $2==i{print $12 "," $13; exit}
    ' "$PLAN")"

    [ "$addr" = "$expected" ] || die "$conf: Address mismatch"

    port="$(awk -F' = ' '/^ListenPort/{print $2}' "$conf")"
    [ "$port" -eq $((51420 + ifnum)) ] || die "$conf: ListenPort mismatch"

    grep -Eq 'PostUp|PostDown|Table|FwMark' "$conf" \
        && die "$conf: forbidden directive present"
done

# --------------------------------------------------------------------
# Server peer validation
# --------------------------------------------------------------------

declare -A SEEN_PUB

for iface_dir in "$OUT/server/peers/"wg*; do
    iface="$(basename "$iface_dir")"
    for conf in "$iface_dir/"*.conf; do
        base="$(basename "$conf" .conf)"
        key="$base|$iface"

        allowed="$(awk -F' = ' '/^AllowedIPs/{print $2}' "$conf")"
        [ "$allowed" = "${PLAN[$key.server_allowed]}" ] \
            || die "$conf: AllowedIPs mismatch"

        pub="$(awk -F' = ' '/^PublicKey/{print $2}' "$conf")"
        [ -n "$pub" ] || die "$conf: empty PublicKey"

        if [ -n "${SEEN_PUB[$pub]:-}" ]; then
            die "duplicate server peer public key $pub"
        fi
        SEEN_PUB["$pub"]=1

        if grep -q '10.89.12.0/24' <<<"$allowed"; then
            [ "${PLAN[$key.lan]}" = "lan_access" ] \
                || die "$conf: LAN route without intent"
        fi
    done
done

echo "✅ wg-check-rendered: all rendered artifacts validated"
