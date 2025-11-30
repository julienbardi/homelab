#!/usr/bin/env bash
# /lib/run_as_root.sh
# Execute one command as root, optionally preserving environment.
# --------------------------------------------------------------------
# CONTRACT:
# - Provides run_as_root() function for scripts (argv tokens contract).
# - Optional first argument: --preserve to keep environment under sudo.
# - In Makefiles, mk/01_common.mk sets run_as_root := ./bin/run-as-root.
# - All calls must pass argv tokens (program + args), not a single quoted string.
# - Escape operators (\>, \|, \&\&, \|\|) in Make recipes so they survive parsing.
# --------------------------------------------------------------------
# Usage:
#   run_as_root <program> [args...]
#   run_as_root --preserve <program> [args...]
#
# Examples:
#   run_as_root systemctl restart unbound
#   run_as_root --preserve env | grep PATH

set -euo pipefail

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [${0##*/}] $*"
}

run_as_root_OLD() {
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

run_as_root() {
	local preserve=false
	if [[ "${1:-}" == "--preserve" ]]; then
		preserve=true
		shift
	fi

	if [ "$(id -u)" -eq 0 ]; then
		if $preserve; then
			exec env -i "$@"
		else
			exec "$@"
		fi
	else
		if $preserve; then
			exec sudo -E -- "$@"
		else
			exec sudo -- "$@"
		fi
	fi
}


run_as_root "$@"
