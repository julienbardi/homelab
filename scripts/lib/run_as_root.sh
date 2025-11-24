#!/usr/bin/env bash

log() {
	# Print timestamp + script name in same format as common.sh
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME:-${0##*/}}] $*"
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
