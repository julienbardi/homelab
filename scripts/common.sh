#!/bin/bash
# ============================================================
# common.sh
# ------------------------------------------------------------
# Shared helpers for homelab scripts
# Provides: log(), run_as_root(), ensure_rule()
# ============================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE="${LOG_FILE:-/var/log/homelab/${SCRIPT_NAME}.log}"
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [${0##*/}] $*"
    echo "$msg"
    if [[ -n "${LOGFILE:-}" ]]; then
        echo "$msg" >> "$LOGFILE"
    fi
}

log() {
	# Send logs to stderr so stdout stays clean for command output
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] $*" | tee -a "${LOG_FILE}" >&2
	logger -t "${SCRIPT_NAME}" "$*"
}

run_as_root() {
	if [[ "${1:-}" == "--preserve" ]]; then
		shift
		log "Executing with sudo -E (preserve env): $*"
		sudo -E bash -c "$*"
	else
		# Detect if command contains shell operators (&&, ||, ;)
		if [[ "$*" =~ [\&\|\;] ]]; then
			log "Executing with sudo (shell): $*"
			sudo bash -c "$*"
		else
			log "Executing with sudo: $*"
			sudo "$@"
		fi
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
