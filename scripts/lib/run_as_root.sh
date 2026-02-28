#!/usr/bin/env bash
# run_as_root.sh — Execute command as root, optionally preserving environment.
# --------------------------------------------------------------------
# CONTRACT:
# - Provides run_as_root() function for scripts (argv tokens contract).
# - Optional first argument: --preserve to keep environment under sudo.
# - In Makefiles, mk/01_common.mk sets run_as_root := ./bin/run-as-root.
# - All calls must pass argv tokens (program + args), not a single quoted string.
# - Escape operators (\>, \|, \&\&, \|\|) in Make recipes so they survive parsing.
# --------------------------------------------------------------------
# Usage:
#   run_as_root <program> [args...]
#   run_as_root --preserve <program> [args...]
#
# Examples:
#   run_as_root systemctl restart unbound
#   run_as_root --preserve printenv PATH

run_as_root() {
	local preserve=false

	# Check if --preserve is first arg
	if [[ "${1:-}" == "--preserve" ]]; then
		preserve=true
		shift
	fi

	# Validate at least one argument
	if [ $# -eq 0 ]; then
		echo "run_as_root: no command provided" >&2
		return 1
	fi

	# If already root, run directly
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		# Use sudo
		if [[ "$preserve" == true ]]; then
			sudo -E -- "$@"
		else
			sudo -- "$@"
		fi
	fi
}

# Only run when executed directly, not when sourced
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	set -euo pipefail
	run_as_root "$@"
fi