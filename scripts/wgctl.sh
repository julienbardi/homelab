#!/bin/bash
# scripts/wgctl.sh
# Unified WireGuard control-plane for NAS + router
set -euo pipefail

SCRIPT_NAME="wgctl"
# shellcheck disable=SC1091
source /usr/local/bin/common.sh

ROLE="${1:-}"
ACTION="${2:-}"

usage() {
    cat >&2 <<EOF
Usage: wgctl.sh <nas|router> <install|up|down|status>

Examples:
  wgctl.sh nas install
  wgctl.sh nas up
  wgctl.sh nas down
  wgctl.sh nas status

  wgctl.sh router install
  wgctl.sh router up
  wgctl.sh router down
  wgctl.sh router status
EOF
    exit 1
}

[[ -z "$ROLE" || -z "$ACTION" ]] && usage

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"
OUTPUT_SERVER="${ROOT_DIR}/output/server"
OUTPUT_ROUTER="${ROOT_DIR}/output/router}"

NAS_WG_DIR="/etc/wireguard"
ROUTER_WG_DIR="/jffs/etc/wireguard"

ROUTER_HOST="${ROUTER_HOST:-julie@10.89.12.1}"
ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-2222}"

OWNER="root"
GROUP="root"
MODE="0600"

require_nas_control_plane() {
    if [[ "${NAS_CONTROL_PLANE:-}" != "1" ]]; then
        log "❌ wgctl.sh nas * must be executed via the NAS control plane"
        log "   (use: make nas-converge or a nas-* target)"
        exit 1
    fi
}

require_router_control_plane() {
    if [[ "${ROUTER_CONTROL_PLANE:-}" != "1" ]]; then
        log "❌ wgctl.sh router * must be executed via the router control plane"
        log "   (use: make router-converge or a router-* target)"
        exit 1
    fi
}

select_ifaces() {
    local role="$1"
    local -n _out_ref=$2

    local host_filter
    case "$role" in
        nas)    host_filter="nas" ;;
        router) host_filter="router" ;;
        *)      log "❌ Invalid role for select_ifaces: $role"; exit 1 ;;
    esac

    mapfile -t _out_ref < <(
        awk -F'\t' -v host="$host_filter" '
            $1 !~ /^#/ && $1 != "iface" && $2 == host && $7 == "1" { print $1 }
        ' "${INPUT_DIR}/wg-interfaces.tsv"
    )
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------

do_install_nas() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No NAS interfaces found in wg-interfaces.tsv"
        return 0
    fi

    run_as_root mkdir -p "${NAS_WG_DIR}"

    for iface in "${ifaces[@]}"; do
        local src="${OUTPUT_SERVER}/${iface}.conf"
        local dst="${NAS_WG_DIR}/${iface}.conf"

        require_file "${src}"
        run_as_root install -m 600 "${src}" "${dst}"
        log "Installed NAS config ${iface}.conf → ${dst}"
    done

    # Deploy NAS firewall script
    local fw_src="${OUTPUT_SERVER}/firewall-nas.sh"
    local fw_dst="${NAS_WG_DIR}/firewall-nas.sh"
    require_file "${fw_src}"
    run_as_root install -m 755 "${fw_src}" "${fw_dst}"
    log "Installed NAS firewall script → ${fw_dst}"
}

do_install_router() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No router interfaces found in wg-interfaces.tsv"
        return 0
    fi

    local changed=0
    local args=()

    for iface in "${ifaces[@]}"; do
        local src="${OUTPUT_ROUTER}/${iface}.conf"
        local dst="${ROUTER_WG_DIR}/${iface}.conf"

        require_file "${src}"

        args+=("" "" "${src}" "${ROUTER_HOST}" "${ROUTER_SSH_PORT}" "${dst}" "${OWNER}" "${GROUP}" "${MODE}")
        log "Planned router install ${iface}.conf → ${dst}"
    done

    install_files_if_changed_v2 changed "${args[@]}"

    if [[ "$changed" -eq 1 ]]; then
        log "🚀 Router WireGuard config(s) updated"
    else
        log "⚪ Router WireGuard config(s) already up-to-date"
    fi

    # Deploy router firewall script
    local fw_src="${OUTPUT_ROUTER}/firewall-router.sh"
    local fw_dst="/jffs/etc/wireguard/firewall-router.sh"
    local fw_changed=0

    install_files_if_changed_v2 fw_changed \
        "" "" "${fw_src}" "${ROUTER_HOST}" "${ROUTER_SSH_PORT}" "${fw_dst}" "${OWNER}" "${GROUP}" "0755"

    if [[ "$fw_changed" -eq 1 ]]; then
        log "🚀 Router firewall script updated"
    else
        log "⚪ Router firewall script already up-to-date"
    fi
}

# ---------------------------------------------------------------------------
# NAS: UP / DOWN / STATUS
# ---------------------------------------------------------------------------

do_up_nas() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No NAS interfaces found in wg-interfaces.tsv"
        return 0
    fi

    for iface in "${ifaces[@]}"; do
        local wg_conf="${NAS_WG_DIR}/${iface}.conf"

        require_file "${wg_conf}"

        log "🔧 Bringing up NAS interface ${iface}"

        if ip link show "${iface}" >/dev/null 2>&1; then
            log "   Tearing down stale ${iface}"
            run_as_root ip link set "${iface}" down || true
            run_as_root ip link del "${iface}" || true
        fi

        run_as_root ip link add "${iface}" type wireguard
        run_as_root wg setconf "${iface}" "${wg_conf}"

        local addr_line
        addr_line=$(grep '^Address' "${wg_conf}" | cut -d'=' -f2 | tr -d ' ')
        for addr in $addr_line; do
            run_as_root ip address add "$addr" dev "${iface}"
        done

        run_as_root ip link set "${iface}" up
        log "   ${iface} is up"
    done

    if [[ -x "${NAS_WG_DIR}/firewall-nas.sh" ]]; then
        run_as_root "${NAS_WG_DIR}/firewall-nas.sh"
        log "🔥 NAS firewall reconciled"
    else
        log "⚠️ NAS firewall script not found or not executable: ${NAS_WG_DIR}/firewall-nas.sh"
    fi

    log "✅ NAS WireGuard interfaces are up"
}

do_down_nas() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No NAS interfaces found in wg-interfaces.tsv"
        return 0
    fi

    for iface in "${ifaces[@]}"; do
        log "🔻 Bringing down NAS interface ${iface}"

        if ip link show "${iface}" >/dev/null 2>&1; then
            run_as_root ip link set "${iface}" down || true
            run_as_root ip link del "${iface}" || true
            log "   ${iface} torn down"
        else
            log "   ${iface} not present"
        fi
    done

    log "✅ NAS WireGuard interfaces are down"
}

do_status_nas() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No NAS interfaces found in wg-interfaces.tsv"
        return 0
    fi

    log "📡 Querying NAS WireGuard status"

    for iface in "${ifaces[@]}"; do
        log ""
        log "=== NAS WireGuard Status (${iface}) ==="

        if ip link show "${iface}" >/dev/null 2>&1; then
            log "Interface: PRESENT"
        else
            log "Interface: NOT PRESENT"
            continue
        fi

        local state ipv4 ipv6
        state=$(ip link show "${iface}" | awk '/state/ {print $9}')
        ipv4=$(ip -4 addr show "${iface}" | awk '/inet / {print $2}')
        ipv6=$(ip -6 addr show "${iface}" | awk '/inet6 / {print $2}')

        log "State: ${state:-unknown}"
        log "IPv4: ${ipv4:-none}"
        log "IPv6: ${ipv6:-none}"

        log "--- wg show ---"
        wg show "${iface}" || log "wg show failed"

        log "=== End (${iface}) ==="
    done

    log "📡 NAS WireGuard status complete"
}

# ---------------------------------------------------------------------------
# ROUTER: UP / DOWN / STATUS
# ---------------------------------------------------------------------------

do_up_router() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No router interfaces found in wg-interfaces.tsv"
        return 0
    fi

    log "🚀 Bringing up router WireGuard interfaces: ${ifaces[*]}"

    ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

for IFACE in ${ifaces[*]}; do
    WG_CONF="${ROUTER_WG_DIR}/\${IFACE}.conf"

    echo "[router-wg-up] Using config: \${WG_CONF}"

    if [ ! -f "\${WG_CONF}" ]; then
        echo "❌ Missing router WireGuard config: \${WG_CONF}" >&2
        exit 1
    fi

    if ip link show "\${IFACE}" >/dev/null 2>&1; then
        ip link set "\${IFACE}" down || true
        ip link del "\${IFACE}" || true
    fi

    ip link add "\${IFACE}" type wireguard
    wg setconf "\${IFACE}" "\${WG_CONF}"

    ADDR_LINE=\$(grep '^Address' "\${WG_CONF}" | cut -d'=' -f2 | tr -d ' ')
    for addr in \$ADDR_LINE; do
        ip address add "\$addr" dev "\${IFACE}"
    done

    ip link set "\${IFACE}" up
    echo "[router-wg-up] Interface \${IFACE} is up"
done
EOF

    ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" "/jffs/etc/wireguard/firewall-router.sh" || \
        log "⚠️ Router firewall script failed or missing"

    log "✅ Router WireGuard interfaces are up"
}

do_down_router() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No router interfaces found in wg-interfaces.tsv"
        return 0
    fi

    log "🔻 Bringing down router WireGuard interfaces: ${ifaces[*]}"

    ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

for IFACE in ${ifaces[*]}; do
    if ip link show "\${IFACE}" >/dev/null 2>&1; then
        ip link set "\${IFACE}" down || true
        ip link del "\${IFACE}" || true
        echo "[router-wg-down] \${IFACE} torn down"
    else
        echo "[router-wg-down] \${IFACE} not present"
    fi
done
EOF

    log "✅ Router WireGuard interfaces are down"
}

do_status_router() {
    local ifaces=("$@")

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        log "No router interfaces found in wg-interfaces.tsv"
        return 0
    fi

    log "📡 Querying router WireGuard status for: ${ifaces[*]}"

    ssh -p "${ROUTER_SSH_PORT}" "${ROUTER_HOST}" /bin/sh <<EOF
set -eu

for IFACE in ${ifaces[*]}; do
    echo ""
    echo "=== Router WireGuard Status (\$IFACE) ==="

    if ip link show "\$IFACE" >/dev/null 2>&1; then
        echo "Interface: PRESENT"
    else
        echo "Interface: NOT PRESENT"
        continue
    fi

    STATE=\$(ip link show "\$IFACE" | awk '/state/ {print \$9}')
    echo "State: \${STATE:-unknown}"

    IPV4=\$(ip -4 addr show "\$IFACE" | awk '/inet / {print \$2}')
    IPV6=\$(ip -6 addr show "\$IFACE" | awk '/inet6 / {print \$2}')
    echo "IPv4: \${IPV4:-none}"
    echo "IPv6: \${IPV6:-none}"

    echo "--- wg show ---"
    wg show "\$IFACE" || echo "wg show failed"

    echo "=== End (\$IFACE) ==="
done
EOF

    log "📡 Router WireGuard status complete"
}

# ---------------------------------------------------------------------------
# MAIN DISPATCH
# ---------------------------------------------------------------------------

main() {
    case "$ROLE" in
        nas)
            require_nas_control_plane
            ;;
        router)
            require_router_control_plane
            ;;
        *)
            log "❌ Invalid role: ${ROLE}"
            usage
            ;;
    esac

    local ifaces=()
    select_ifaces "$ROLE" ifaces

    case "$ROLE:$ACTION" in
        nas:install)    do_install_nas    "${ifaces[@]}" ;;
        nas:up)         do_up_nas         "${ifaces[@]}" ;;
        nas:down)       do_down_nas       "${ifaces[@]}" ;;
        nas:status)     do_status_nas     "${ifaces[@]}" ;;
        router:install) do_install_router "${ifaces[@]}" ;;
        router:up)      do_up_router      "${ifaces[@]}" ;;
        router:down)    do_down_router    "${ifaces[@]}" ;;
        router:status)  do_status_router  "${ifaces[@]}" ;;
        *)
            log "❌ Invalid combination: ${ROLE} ${ACTION}"
            usage
            ;;
    esac
}

main "$@"
