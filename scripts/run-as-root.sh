#!/usr/bin/env bash
# --------------------------------------------------------------------
# bin/run-as-root
# --------------------------------------------------------------------
# CONTRACT:
# - Accepts argv tokens, not a single quoted string.
# - Preserves argument boundaries exactly.
# - If already root: exec "$@".
# - If not root: exec sudo -- "$@".
# - This allows commands with arguments, quotes, >, |, &&, ||.
# - In Makefiles, escape operators (\>, \|, \&\&) so they survive parsing.
# --------------------------------------------------------------------
set -euo pipefail

# 1. Require at least one argument (command)
if [ "$#" -eq 0 ]; then
	echo "run-as-root: no command specified" >&2
	exit 64
fi

# 2. Policy: which env vars may cross the privilege boundary
PRESERVE_ENV="DEBIAN_FRONTEND,SRC_ATTIC_CONFIG,SRC_ATTIC_SERVICE,ATTIC_REF,WG_ROOT,VERBOSE,HOMELAB_DIR,ROUTER_ADDR,ROUTER_USER,ROUTER_SSH_PORT,SSH_OPTS"

# 3. Already root → exec directly
if [ "$(id -u)" -eq 0 ]; then
	exec "$@"
fi

# 4. Not root → require sudo
if ! command -v sudo >/dev/null 2>&1; then
	echo "run-as-root: sudo not found and not running as root" >&2
	exit 69
fi

# 5. Exec sudo with preserved env and clear semantics
exec sudo --preserve-env="$PRESERVE_ENV" -- "$@"
