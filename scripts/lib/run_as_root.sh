#!/usr/bin/env bash
# run_as_root.sh
log() {
	# Print timestamp + script name in same format as common.sh
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME:-${0##*/}}] $*"
}


run_as_root() {
	local preserve=false
	if [[ "${1:-}" == "--preserve" ]]; then
		preserve=true
		shift
	fi

	if [[ $# -ne 1 ]]; then
		log "ERROR: run_as_root expects a single quoted command string (or --preserve + command)"
		return 1
	fi

	local cmd="$1"
	log "Executing with sudo${preserve:+ -E}: $cmd"

	if $preserve; then
		sudo -E bash -c "$cmd"
	else
		sudo bash -c "$cmd"
	fi
}

