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
    newhash="$(sha256sum "${file}" | cut -d' ' -f1)"
    if [[ ! -f "${hashfile}" ]] || [[ "$(cat "${hashfile}")" != "$newhash" ]]; then
        echo "$newhash" | sudo tee "${hashfile}" >/dev/null
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
    local dir_user="${7:-root}"
    local dir_group="${8:-root}"
    local dir_mode="${9:-0755}"

    local user="${owner_group%%:*}"
    local group="${owner_group##*:}"
    local src_hash
    local dest_dir
    local remote_tmp

    if [[ ! -r "${src}" ]]; then
        log "⚪ atomic_install: source file missing or not readable, skipping: ${src}"
        return 0
    fi

    src_hash=$(sha256sum "${src}" | awk '{print $1}')
    dest_dir="$(dirname "${dest}")"
    # ------------------------------------------------------------
    # Localhost Case
    # ------------------------------------------------------------
    if [[ "${host}" == "localhost" ]]; then
        sudo install -d -o "${dir_user}" -g "${dir_group}" -m "${dir_mode}" "${dest_dir}"
        if cmp -s "${src}" "${dest}" 2>/dev/null; then
            log "💎 ${dest} unchanged"
            logger -t "${SCRIPT_NAME}" "DETAILS: unchanged dest=${dest}, hash=${src_hash}"
            echo "unchanged"
            return 0
        fi

        log "✅ ${dest} updated"
        logger -t "${SCRIPT_NAME}" "DETAILS: src=${src}, dest=${dest}, hash=${src_hash}"
        sudo install -o "${user}" -g "${group}" -m "${mode}" "${src}" "${dest}"
        echo "changed"
        return 0
    fi

    # ------------------------------------------------------------
    # Remote Case (Single SSH check + Single SSH atomic install)
    # ------------------------------------------------------------
    # Create remote directory
    ssh -p "${port}" "${host}" "sudo install -d -o '${dir_user}' -g '${dir_group}' -m '${dir_mode}' '${dest_dir}'"

    # Check if remote file matches local source
    if ssh -p "${port}" "${host}" "[[ -f \"${dest}\" ]] && cmp -s \"${dest}\"" < "${src}" 2>/dev/null; then
        log "💎 ${host}:${dest} unchanged"
        logger -t "${SCRIPT_NAME}" "DETAILS: remote unchanged dest=${dest}, hash=${src_hash}"
        echo "unchanged"
        return 0
    fi

    # Update required
    remote_tmp="/tmp/$(date -u +%Y-%m-%d_%H-%M-%S)-atomic_install-$(uuidgen)-$(basename "${src}")"

    if [[ "${host}" == "localhost" ]]; then
        # Local cleanup
        now=$(date -u +%s)
        threshold=$((now - 86400))  # 24 hours in seconds

        for file in /tmp/*-atomic_install-*; do
            [[ -f "$file" ]] || continue

            base=$(basename "$file")

            # Validate prefix timestamp format before parsing
            if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2} ]]; then
                prefix_time_str=${base:0:19}
                prefix_time_epoch=$(date -u -d "$prefix_time_str" +%s 2>/dev/null || echo 0)
            else
                prefix_time_epoch=0
            fi

            file_mtime_epoch=$(stat -c %Y "$file" 2>/dev/null || echo 0)

            if (( prefix_time_epoch > 0 && prefix_time_epoch < threshold )) && (( file_mtime_epoch > 0 && file_mtime_epoch < threshold )); then
                rm -f "$file"
                continue
            fi
        done

    else
        # Remote cleanup via SSH
        ssh -p "${port}" "${host}" bash -c "'
now=\$(date -u +%s)
threshold=\$((now - 86400))  # 24 hours in seconds

for file in /tmp/*-atomic_install-*; do
    [[ -f \"\$file\" ]] || continue

    base=\$(basename \"\$file\")

    if [[ \"\$base\" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2} ]]; then
        prefix_time_str=\${base:0:19}
        prefix_time_epoch=\$(date -u -d \"\$prefix_time_str\" +%s 2>/dev/null || echo 0)
    else
        prefix_time_epoch=0
    fi

    file_mtime_epoch=\$(stat -c %Y \"\$file\" 2>/dev/null || echo 0)

    if (( prefix_time_epoch > 0 && prefix_time_epoch < threshold )) && (( file_mtime_epoch > 0 && file_mtime_epoch < threshold )); then
        rm -f \"\$file\"
        continue
    fi
done
'"
    fi



    log "✅ ${host}:${dest} (updating)"
    logger -t "${SCRIPT_NAME}" "DETAILS: remote src=${src}, dest=${dest}, hash=${src_hash}"

    # 1. Transfer to temporary location
    if ! scp -P "${port}" -q "${src}" "${host}:${remote_tmp}"; then
      log "❌ SCP failed to copy ${src} to ${host}:${remote_tmp}"
      return 1
    fi

    # 2. Atomic install + Cleanup in one SSH call
    # This ensures ownership and permissions are set before the file is visible at ${dest}
    if ! ssh -p "${port}" "${host}" "sudo install -o '${user}' -g '${group}' -m '${mode}' '${remote_tmp}' '${dest}' && rm -f '${remote_tmp}'"; then
      log "❌ Remote install failed on ${host} for ${dest}"
      return 1
    fi

    echo "changed"
    return 0
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