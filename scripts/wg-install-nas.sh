#!/usr/bin/env bash
# scripts/wg-install-nas.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_DIR="${ROOT_DIR}/input"
OUTPUT_DIR="${ROOT_DIR}/output/server"

NAS_WG_DIR="/etc/wireguard"

log() {
    printf '[wg-install-nas] %s\n' "$*" >&2
}

log "Installing NAS WireGuard configs"

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

# --- Install each NAS interface --------------------------------------------

sudo mkdir -p "${NAS_WG_DIR}"

for iface in "${NAS_IFACES[@]}"; do
    SRC="${OUTPUT_DIR}/${iface}.conf"
    DST="${NAS_WG_DIR}/${iface}.conf"

    if [[ ! -f "${SRC}" ]]; then
        log "ERROR: Missing generated config: ${SRC}"
        exit 1
    fi

    sudo install -m 600 "${SRC}" "${DST}"
    log "Installed ${iface}.conf → ${DST}"
done

log "NAS installation complete"
