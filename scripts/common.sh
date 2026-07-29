#!/bin/bash
# ============================================================
# common.sh — shared primitives for homelab scripts
#
# This file defines:
#   - secure environment loading
#   - deterministic logging
#   - privilege‑correct root escalation
#   - idempotent rule insertion
#   - certificate‑deployment helpers
#
# All helpers here must remain:
#   - side‑effect minimal
#   - privilege‑bounded
#   - reproducible
#   - safe under sudo and non‑sudo execution
# ============================================================

set -euo pipefail

# Prevent double‑loading when sourced multiple times
[[ -n "${_HOMELAB_COMMON_SH_LOADED:-}" ]] && return
readonly _HOMELAB_COMMON_SH_LOADED=1

# ============================================================
# 1. Secure environment loading (operator‑based trust model)
# ============================================================

HOMELAB_ENV="/root/src/homelab/config/homelab.env"

# Trusted users: root + operators
TRUSTED_USERS=("root" "julie" "leona")

if [[ -f "$HOMELAB_ENV" ]]; then
	_env_owner_uid=$(stat -c "%u" "$HOMELAB_ENV")
	_env_group_gid=$(stat -c "%g" "$HOMELAB_ENV")
	_env_mode=$(stat -c "%a" "$HOMELAB_ENV")

	# Extract octal digits
	_env_o=${_env_mode:0:1}
	_env_g=${_env_mode:1:1}
	_env_t=${_env_mode:2:1}

	# Resolve trusted user UIDs
	TRUSTED_UIDS=()
	for u in "${TRUSTED_USERS[@]}"; do
		uid=$(id -u "$u" 2>/dev/null || true)
		[[ -n "$uid" ]] && TRUSTED_UIDS+=("$uid")
	done

	# Check owner trust
	owner_trusted=false
	for uid in "${TRUSTED_UIDS[@]}"; do
		[[ "$_env_owner_uid" == "$uid" ]] && owner_trusted=true
	done

	# Check group trust (any trusted user in that group)
	group_trusted=false
	for u in "${TRUSTED_USERS[@]}"; do
		id -G "$u" 2>/dev/null | tr ' ' '\n' | grep -qx "$_env_group_gid" && group_trusted=true
	done

	if ! $owner_trusted && ! $group_trusted; then
		echo "[common.sh] WARNING: $HOMELAB_ENV owner/group untrusted — skipping source" >&2

	elif (( _env_t >= 2 )); then
		echo "[common.sh] WARNING: $HOMELAB_ENV world-writable ($_env_mode) — skipping source" >&2

	elif (( _env_g >= 2 )) && ! $group_trusted; then
		echo "[common.sh] WARNING: $HOMELAB_ENV group-writable by untrusted group ($_env_mode) — skipping source" >&2

	else
		# Safe to load
		_saved_path="$PATH"
		set -a
		source "$HOMELAB_ENV"
		set +a
		PATH="$_saved_path"
		unset _saved_path
	fi

	unset _env_owner_uid _env_group_gid _env_mode _env_o _env_g _env_t
fi

export ACME_HOME
export SSL_CERT_ECC SSL_CHAIN_ECC SSL_KEY_ECC

# ============================================================
# 2. Derived defaults
# ============================================================

# Router SSH helper (only set if not already defined)
: "${ROUTER_SSH:=ssh -p${ROUTER_SSH_PORT:-2222} ${ROUTER_HOST:-}}"
export ROUTER_SSH

# SCRIPT_NAME:
#   - If user sets SCRIPT_NAME="", logging becomes minimalist
#   - If unset, derive from BASH_SOURCE (correct for sourced scripts)
if [ "${SCRIPT_NAME+set}" != "set" ]; then
	SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
fi

# Exit code used by IFCv3 to signal "changed"
export INSTALL_IF_CHANGED_EXIT_CHANGED=3

# Path to IFCv3 installer (vectorized v2 wrapper depends on this)
: "${INSTALL_FILE_IF_CHANGED:=/usr/local/bin/install_file_if_changed_v3.sh}"

export INSTALL_FILE_IF_CHANGED

# ============================================================
# 3. Logging + privilege helpers
# ============================================================

log() {
	# Minimalist mode: SCRIPT_NAME=""
	if [ "${SCRIPT_NAME+set}" = "set" ] && [ -z "$SCRIPT_NAME" ]; then
		printf "%s\n" "$*" >&2
	else
		printf "[%s] %s\n" "${SCRIPT_NAME:-$(basename "$0" .sh)}" "$*" >&2
	fi

	# Optional syslog integration
	command -v logger >/dev/null 2>&1 && \
		logger -t homelab "${SCRIPT_NAME:-${0##*/}}: $*"
}

# Privilege boundary:
#   - If already root, run directly
#   - Otherwise escalate via sudo
run_as_root() {
	if [[ $EUID -eq 0 ]]; then
		"$@"
	else
		sudo "$@"
	fi
}

# Idempotent rule insertion:
#   - Uses iptables/nftables -C to check before inserting
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
# 4. Certificate‑deployment helpers
# ============================================================

# Require file exists and is non‑empty
require_file() {
	[[ -s "$1" ]] || { log "❌ missing file: $1"; exit 1; }
}

# Reload service with correct fallback order:
#   1. caddy reload (only for caddy)
#   2. systemctl reload
#   3. systemctl restart
reload_service() {
	local svc="$1"
	local config="$2"

	if [[ "$svc" == "caddy" ]]; then
		if sudo timeout 10 caddy reload --config "${config}" --force; then
			log "${svc} reloaded via caddy CLI"
			return 0
		fi
		log "${svc} caddy CLI reload failed, falling back to systemctl..."
	fi

	if sudo timeout 10 systemctl reload "${svc}"; then
		log "${svc} reloaded via systemctl"
		return 0
	fi

	log "${svc} reload unsupported — restarting"

	if sudo timeout 10 systemctl restart "${svc}"; then
		log "${svc} restarted via systemctl"
		return 0
	fi

	log "❌ ${svc} reload/restart failed completely"
	return 1
}

# Require a binary to exist in PATH
require_bin() {
	local bin="$1"
	local reason="${2:-Required for operation}"
	if ! command -v "${bin}" >/dev/null 2>&1; then
		log "❌ binary missing: ${bin} (${reason})"
		log "ℹ️ ➡️ Fix with: make prereqs"
		exit 1
	fi
}
