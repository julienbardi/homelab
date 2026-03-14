#!/bin/bash
# ============================================================
# common.sh
# ------------------------------------------------------------
# Shared helpers for homelab scripts
# Provides: log(), run_as_root(), ensure_rule()
# ============================================================
set -euo pipefail

[[ -n "${_HOMELAB_COMMON_SH_LOADED:-}" ]] && return
readonly _HOMELAB_COMMON_SH_LOADED=1

# Only set a default if SCRIPT_NAME is completely unset.
# If it is set to "" (empty), we respect that for minimalist logging.
if [ "${SCRIPT_NAME+set}" != "set" ]; then
    SCRIPT_NAME="$(basename "$0" .sh)"
fi

export INSTALL_IF_CHANGED_EXIT_CHANGED=3

# shellcheck disable=SC2317
log() {
    if [ "${SCRIPT_NAME+set}" = "set" ] && [ -z "$SCRIPT_NAME" ]; then
        # Minimalist mode: No brackets, just the message (preserves icons)
        printf "%s\n" "$*" >&2
    else
        # Explicit or Default: [name] message
        printf "[%s] %s\n" "${SCRIPT_NAME:-$(basename "$0" .sh)}" "$*" >&2
    fi

    command -v logger >/dev/null 2>&1 && logger -t homelab "${SCRIPT_NAME:-${0##*/}}: $*"
}

# Idempotent rule inserter: checks with -C first
ensure_rule() {
    local cmd="$1"; shift
    local args=("$@")
    if "$cmd" -C "${args[@]}" 2>/dev/null; then
        log "Rule already present: $cmd ${args[*]}"
    else
        "$cmd" "${args[@]}"
        log "Rule added: $cmd ${args[*]}"
    fi
}

# ============================================================
# Extra helpers for certificate deployment
# ------------------------------------------------------------
# These are additive; existing functions above remain untouched
# ============================================================

# Require file exists and is non-empty
require_file() {
    [[ -s "$1" ]] || { log "❌ missing file: $1"; exit 1; }
}

# Compare hash of source file against stored hash file
# Returns 0 if changed, 1 if unchanged
changed() {
    local file="$1" hashfile="$2"
    local newhash
    newhash="$(sha256sum "${file}" | cut -d' ' -f1)"
    if [[ ! -f "${hashfile}" ]] || [[ "$(cat "${hashfile}")" != "$newhash" ]]; then
        echo "$newhash" | sudo tee "${hashfile}" >/dev/null
        return 0
    fi
    return 1
}

# Restart service only if cert changed
restart_if_CANDIDATE_FOR_DELETION() {
    local svc="$1" changed="$2"
    if [[ "${changed}" == "1" ]]; then
        if ! sudo timeout 10 caddy reload --config /etc/caddy/Caddyfile --force; then
            log "caddy reload via CLI failed, trying systemctl..."
            sudo timeout 10 systemctl reload "${svc}" || sudo timeout 10 systemctl restart "${svc}"
        fi
        log "${svc} reloaded/restarted"
    else
        log "${svc} unchanged; no restart"
    fi
}

reload_service() {
    local svc="$1"
    local config="$2"

    # Try caddy reload with timeout
    if sudo timeout 10 caddy reload --config "${config}" --force; then
        log "${svc} reloaded via caddy CLI"
        return 0
    fi

    log "${svc} reload via CLI failed, trying systemctl..."

    # Fallback: systemctl reload with timeout
    if sudo timeout 10 systemctl reload "${svc}"; then
        log "${svc} reloaded via systemctl"
        return 0
    fi

    # Final fallback: systemctl restart with timeout
    if sudo timeout 10 systemctl restart "${svc}"; then
        log "${svc} restarted via systemctl"
        return 0
    fi

    log "❌ ${svc} reload/restart failed completely"
    return 1
}

# Require a binary exists in PATH
# Usage: require_bin funzip "Required for Tranco list extraction"
require_bin() {
    local bin="$1"
    local reason="${2:-Required for operation}"
    if ! command -v "${bin}" >/dev/null 2>&1; then
        log "❌ binary missing: ${bin} (${reason})"
        log "ℹ️ 👉 Fix with: make prereqs"
        exit 1
    fi
}

install_files_if_changed_v2() {
    local -n _changed_ref=$1  # Added underscore to prevent name collision
    shift
    local total_args=$#

	# Precision check: Ensure the installer exists before processing the vector
    require_file "/usr/local/bin/install_file_if_changed_v2.sh"

    for (( i=1; i<=total_args; i+=9 )); do
        set +e
        /usr/local/bin/install_file_if_changed_v2.sh -q "${@:i:9}"
        local rc=$?
        set -e

        if [[ "$rc" -eq "$INSTALL_IF_CHANGED_EXIT_CHANGED" ]]; then
            _changed_ref=1
        elif [[ "$rc" -ne 0 ]]; then
            log "❌ install_file_if_changed_v2.sh failed (rc=$rc) for ${@:i+2:1}"
            exit 1
        fi
    done
}