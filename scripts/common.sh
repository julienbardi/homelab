#!/bin/bash
# ============================================================
# common.sh
# ------------------------------------------------------------
# Shared helpers for homelab scripts
# Provides: log(), run_as_root(), ensure_rule()
# ============================================================

set -euo pipefail

# Force HOME to julie's home even under sudo
HOME="/home/julie"

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE="${LOG_FILE:-/var/log/homelab/${SCRIPT_NAME}.log}"
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

log() {
	local msg="$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME:-${0##*/}}] $*"
	# Print to stderr and append to file if defined
	echo "$msg" | tee -a "${LOG_FILE:-/dev/null}" >&2
	# Send the same formatted message to syslog
	logger -t "${SCRIPT_NAME:-${0##*/}}" "$msg"
}

run_as_root() {
	if [[ "${1:-}" == "--preserve" ]]; then
		shift
		log "Executing with sudo -E (preserve env): $*"
		sudo -E "$@"
	elif [[ "$*" =~ [\&\|\;] ]]; then
		log "Executing with sudo (shell): $*"
		sudo bash -c "$*"
	else
		log "Executing with sudo: $*"
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
	[[ -s "$1" ]] || { log "[ERROR] missing file: $1"; exit 1; }
}

# SHA256 helper
sha256() {
	sha256sum "$1" | awk '{print $1}'
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
atomic_install() {
	local src="$1"
	local dest="$2"
	local owner_group="$3"
	local mode="$4"
	local host="${5:-localhost}"   # optional fifth argument

	# Always compute local source hash for audit
	local src_hash
	src_hash=$(sudo sha256sum "$src" | awk '{print $1}')

	if [[ "$host" == "localhost" ]]; then
		# Local case
		if ! sudo test -f "$dest" || ! sudo cmp -s "$src" "$dest"; then
			local dest_hash=""
			if sudo test -f "$dest"; then
				dest_hash=$(sudo sha256sum "$dest" | awk '{print $1}')
				log "Atomic install: ${src} → localhost:${dest} (owner=${owner_group}, mode=${mode})"
				log "DETAILS: src hash=${src_hash}, dest hash=${dest_hash} (different)"
			else
				log "Atomic install: ${src} → localhost:${dest} (owner=${owner_group}, mode=${mode})"
				log "DETAILS: src hash=${src_hash}, dest missing"
			fi
			sudo install -o "${owner_group%%:*}" -g "${owner_group##*:}" -m "${mode}" "$src" "$dest"
			echo "changed"
			return 0   # success
		else
			log "Atomic install: ${src} → localhost:${dest} unchanged (binary identical, hash=${src_hash})"
			echo "unchanged"
			return 0   # success
		fi
	else
		# Remote case
		if ! ssh "$host" test -f "$dest" || ! ssh "$host" cmp -s "$dest" < "$src"; then
			log "Atomic install: ${src} → ${host}:${dest} (owner=${owner_group}, mode=${mode})"
			log "DETAILS: src hash=${src_hash}, dest different/missing"
			scp "$src" "$host:$dest"
			ssh "$host" sudo chown "${owner_group%%:*}:${owner_group##*:}" "$dest"
			ssh "$host" sudo chmod "$mode" "$dest"
			echo "changed"
			return 0   # success
		else
			log "Atomic install: ${src} → ${host}:${dest} unchanged (binary identical, hash=${src_hash})"
			echo "unchanged"
			return 0   # success
		fi
	fi
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


