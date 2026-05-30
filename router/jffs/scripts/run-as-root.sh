#!/bin/sh
# --------------------------------------------------------------------
# bin/run-as-root.sh — router variant (SSH user is already root)
# --------------------------------------------------------------------
# CONTRACT:
# - Accepts argv tokens, not a single quoted string.
# - Preserves argument boundaries exactly.
# - Executes with whatever UID SSH gives us (Merlin: root).
# - No sudo, no su, no environment juggling.
# - Safe to use with arguments, redirections, pipes, &&, ||.
# --------------------------------------------------------------------

set -e

[ "$#" -gt 0 ] || {
  echo "run-as-root: no command specified" >&2
  exit 64
}

exec "$@"
