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

# ------------------------------------------------------------
# Output icon grammar (operator-facing only)
# ------------------------------------------------------------

readonly ICON_UNCHANGED="◽"

SCRIPT_NAME="$(basename "$0" .sh)"

export INSTALL_IF_CHANGED_EXIT_CHANGED=3
# Run install_if_changed and treat "changed" as success.
# Propagates any other non-zero exit code.
run_install_if_changed() {
    local install_if_changed="$1"; shift
    local rc=0

    "$install_if_changed" "$@" || rc=$?

    if [[ "$rc" -eq 0 || "$rc" -eq "$INSTALL_IF_CHANGED_EXIT_CHANGED" ]]; then
        return 0
    fi

    return "$rc"
}

# shellcheck disable=SC2317
log() {
    local screen_msg="[${SCRIPT_NAME:-${0##*/}}] $*"
    local syslog_msg
    syslog_msg="$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME:-${0##*/}}] $*"

    # Human-friendly output: no timestamp
    echo "$screen_msg" >&2

    # Syslog: keep timestamp for auditability
    logger -t "${SCRIPT_NAME:-${0##*/}}" "$syslog_msg"
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
    [[ -s "$1" ]] || { log "[ERROR] missing file: $1"; exit 1; }
}

# Compare hash of source file against stored hash file
# Returns 0 if changed, 1 if unchanged
changed() {
    local file="$1" hashfile="$2"
    local newhash
    newhash="$(sha256sum "$file" | cut -d' ' -f1)"
    if [[ ! -f "$hashfile" ]] || [[ "$(cat "$hashfile")" != "$newhash" ]]; then
        echo "$newhash" | sudo tee "$hashfile" >/dev/null
        return 0
    fi
    return 1
}

# Atomic install: copy src to dest with owner+mode
# atomic_install SRC DEST OWNER:GROUP MODE [HOST] [PORT]
# Implementation: Local uses 'install', remote uses 'scp' + 'sudo install'.
atomic_install() {
    local src="$1" dest="$2" owner_group="$3" mode="$4"
    local host="${5:-localhost}" port="${6:-22}"

    local user="${owner_group%%:*}"
    local group="${owner_group##*:}"
    local src_hash
    src_hash=$(sha256sum "$src" | awk '{print $1}')

    # ------------------------------------------------------------
    # Localhost Case
    # ------------------------------------------------------------
    if [[ "$host" == "localhost" ]]; then
        if cmp -s "$src" "$dest" 2>/dev/null; then
            log "💎 $dest (unchanged)"
            logger -t "${SCRIPT_NAME}" "DETAILS: unchanged dest=${dest}, hash=${src_hash}"
            echo "unchanged"
            return 0
        fi

        log "✅ $dest (updated)"
        logger -t "${SCRIPT_NAME}" "DETAILS: src=${src}, dest=${dest}, hash=${src_hash}"
        sudo install -o "$user" -g "$group" -m "$mode" "$src" "$dest"
        echo "changed"
        return 0
    fi

    # ------------------------------------------------------------
    # Remote Case (Single SSH check + Single SSH atomic install)
    # ------------------------------------------------------------
    # Check if remote file matches local source
    if ssh -p "$port" "$host" "[[ -f \"$dest\" ]] && cmp -s \"$dest\"" < "$src" 2>/dev/null; then
        log "💎 $host:$dest (unchanged)"
        logger -t "${SCRIPT_NAME}" "DETAILS: remote unchanged dest=${dest}, hash=${src_hash}"
        echo "unchanged"
        return 0
    fi

    # Update required
    local remote_tmp="/tmp/atomic.$(basename "$src").$RANDOM"

    log "✅ $host:$dest (updating)"
    logger -t "${SCRIPT_NAME}" "DETAILS: remote src=${src}, dest=${dest}, hash=${src_hash}"

    # 1. Transfer to temporary location
    scp -P "$port" -q "$src" "$host:$remote_tmp"

    # 2. Atomic install + Cleanup in one SSH call
    # This ensures ownership and permissions are set before the file is visible at $dest
    ssh -p "$port" "$host" "sudo install -o $user -g $group -m $mode $remote_tmp $dest && rm -f $remote_tmp"

    echo "changed"
    return 0
}

# Restart service only if cert changed
restart_if_CANDIDATE_FOR_DELETION() {
    local svc="$1" changed="$2"
    if [[ "$changed" == "1" ]]; then
        if ! sudo timeout 10 caddy reload --config /etc/caddy/Caddyfile --force; then
            log "[svc] caddy reload via CLI failed, trying systemctl..."
            sudo timeout 10 systemctl reload "$svc" || sudo timeout 10 systemctl restart "$svc"
        fi
        log "[svc] $svc reloaded/restarted"
    else
        log "[svc] $svc unchanged; no restart"
    fi
}

reload_service() {
    local svc="$1"
    local config="$2"

    # Try caddy reload with timeout
    if sudo timeout 10 caddy reload --config "$config" --force; then
        log "[svc] $svc reloaded via caddy CLI"
        return 0
    fi

    log "[svc] $svc reload via CLI failed, trying systemctl..."

    # Fallback: systemctl reload with timeout
    if sudo timeout 10 systemctl reload "$svc"; then
        log "[svc] $svc reloaded via systemctl"
        return 0
    fi

    # Final fallback: systemctl restart with timeout
    if sudo timeout 10 systemctl restart "$svc"; then
        log "[svc] $svc restarted via systemctl"
        return 0
    fi

    log "[svc] ERROR: $svc reload/restart failed completely"
    return 1
}

# Require a binary exists in PATH
# Usage: require_bin funzip "Required for Tranco list extraction"
require_bin() {
    local bin="$1"
    local reason="${2:-Required for operation}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "❌ binary missing: $bin ($reason)"
        log "ℹ️ 👉 Fix with: make prereqs"
        exit 1
    fi
}