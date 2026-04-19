#!/usr/bin/env bash
# scripts/wg-install-nas.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"
OUTPUT_DIR="${ROOT_DIR}/output/server"

NAS_WG_DIR="/etc/wireguard"

# shellcheck disable=SC1091
source /usr/local/bin/common.sh
SCRIPT_NAME="wg-install-nas"

log "Installing NAS WireGuard configs (vectorized IFC_v2)"

# --- Determine which interfaces belong to NAS -------------------------------

mapfile -t NAS_IFACES < <(
    awk -F'\t' '
        $1 !~ /^#/ && $1 != "iface" && $2 == "nas" && $7 == "1" { print $1 }
    ' "${INPUT_DIR}/wg-interfaces.tsv"
)

if [[ ${#NAS_IFACES[@]} -eq 0 ]]; then
    log "No NAS interfaces found in wg-interfaces.tsv"
    exit 0
fi

sudo mkdir -p "${NAS_WG_DIR}"

# --- Build IFC_v2 argument vector -------------------------------------------

args=()

for iface in "${NAS_IFACES[@]}"; do
    SRC="${OUTPUT_DIR}/${iface}.conf"
    DST="${NAS_WG_DIR}/${iface}.conf"

    require_file "${SRC}"

    # Append 9-tuple for this file
    args+=("" "" "${SRC}" "" "" "${DST}" "root" "root" "0600")
done

# --- Execute IFC_v2 once -----------------------------------------------------

changed=0
install_files_if_changed_v2 changed "${args[@]}"

if [[ "$changed" -eq 1 ]]; then
    log "🚀 NAS WireGuard configs updated"
else
    log "ℹ️ NAS WireGuard configs already up-to-date"
fi

log "NAS installation complete"
