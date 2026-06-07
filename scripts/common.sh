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

# --- 1. Environment Loading (INSERT HERE) ---
# Load authoritative homelab environment variables
HOMELAB_ENV="/volume1/homelab/homelab.env"
TRUSTED_GROUP="admin"

if [[ -f "$HOMELAB_ENV" ]]; then
    _env_owner=$(stat -c "%u" "$HOMELAB_ENV")
    _env_group=$(stat -c "%g" "$HOMELAB_ENV")
    _env_mode=$(stat -c "%a" "$HOMELAB_ENV")

    current_uid=$(id -u)
    current_gid=$(id -g)
    trusted_gid=$(getent group "$TRUSTED_GROUP" | cut -d: -f3)

    # If trusted_gid is empty, treat as untrusted
    if [[ -z "$trusted_gid" ]]; then
        echo "[common.sh] WARNING: trusted group '$TRUSTED_GROUP' not found — skipping source" >&2
    elif [[ "$_env_owner" != "0" && "$_env_owner" != "$current_uid" && "$_env_group" != "$trusted_gid" ]]; then
        echo "[common.sh] WARNING: $HOMELAB_ENV owner/group not trusted — skipping source" >&2
    elif (( (10#$_env_mode & 002) != 0 )); then
        echo "[common.sh] WARNING: $HOMELAB_ENV is world-writable ($_env_mode) — skipping source" >&2
    elif (( (10#$_env_mode & 020) != 0 )) && [[ "$_env_group" != "$trusted_gid" ]]; then
        echo "[common.sh] WARNING: $HOMELAB_ENV is group-writable by untrusted group ($_env_mode) — skipping source" >&2
    else
        # Save PATH before sourcing so homelab.env cannot hijack it
        _saved_path="$PATH"
        set +a; set +u; set -a
        source "$HOMELAB_ENV"
        set +a; set -u
        PATH="$_saved_path"
        export PATH
        unset _saved_path
    fi

    unset _env_owner _env_group _env_mode
fi


# Set derived router connection string if not already set
: "${ROUTER_SSH:=ssh -p${ROUTER_SSH_PORT:-2222} ${ROUTER_HOST:-}}"
export ROUTER_SSH

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

run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
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

reload_service() {
    local svc="$1"
    local config="$2"

    # Caddy has its own graceful reload CLI; use it only for Caddy itself.
    # Passing a non-Caddy config path to `caddy reload` is incorrect and can
    # silently reload Caddy with wrong configuration.
    if [[ "$svc" == "caddy" ]]; then
        if sudo timeout 10 caddy reload --config "${config}" --force; then
            log "${svc} reloaded via caddy CLI"
            return 0
        fi
        log "${svc} caddy CLI reload failed, falling back to systemctl..."
    fi

    # systemctl reload sends SIGHUP (supported by most daemons)
    if sudo timeout 10 systemctl reload "${svc}"; then
        log "${svc} reloaded via systemctl"
        return 0
    fi

    log "${svc} reload not supported, restarting..."

    # Final fallback: full restart
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

    echo "ARGCOUNT=$# ARGS=[${*}]" >&2
    # Precision check: Ensure the installer exists before processing the vector
    require_file "/usr/local/bin/install_file_if_changed_v2.sh"

    for (( i=1; i<=total_args; i+=9 )); do
        echo "VECTORIZED CALL: ${@:i:9}" >&2
        set +e
        (
            set +e
            "$INSTALL_FILE_IF_CHANGED" "${@:i:9}"
        )
        rc=$?
        set -e
        if [[ "$rc" -eq "$INSTALL_IF_CHANGED_EXIT_CHANGED" ]]; then
            _changed_ref=1
        elif [[ "$rc" -ne 0 ]]; then
            local failed_arg="${@:i+2:1}"
            log "❌ install_file_if_changed_v2.sh failed (rc=$rc) for ${failed_arg}"
            exit 1
        fi
    done
}