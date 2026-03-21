#!/bin/sh
# --------------------------------------------------------------------
# bin/run-as-root.sh — router variant
# --------------------------------------------------------------------
# CONTRACT:
# - Accepts argv tokens, not a single quoted string.
# - Preserves argument boundaries exactly.
# - Always executes as root on the router.
# - No sudo, no environment juggling.
# - Safe to use with arguments, redirections, pipes, &&, ||.
# --------------------------------------------------------------------

set -e

[ "$#" -gt 0 ] || {
	echo "run-as-root: no command specified" >&2
	exit 64
}

exec "$@"
