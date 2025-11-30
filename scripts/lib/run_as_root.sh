#!/usr/bin/env bash
# Execute one command as root, optionally preserving environment.
# Usage:
#   run_as_root.sh "command ..."
#   run_as_root.sh --preserve "command ..."

set -euo pipefail

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${0##*/}] $*"
}

run_as_root() {
	local preserve=false
	if [[ "${1:-}" == "--preserve" ]]; then
		preserve=true
		shift
	fi

	if [[ $# -ne 1 ]]; then
		log "ERROR: expects a single quoted command string"
		exit 1
	fi

	local cmd="$1"
	log "Executing with sudo${preserve:+ -E}: $cmd"

	if $preserve; then
		sudo -E bash -c "$cmd"
	else
		sudo bash -c "$cmd"
	fi
}

run_as_root "$@"
