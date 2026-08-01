#!/usr/bin/env bash
# bin/run-as-root
# --------------------------------------------------------------------
# Privileged escalation wrapper maintaining exact argument isolation.
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

# 2. Establish fully isolated, deterministic root PATH (eliminates inherited pollution)
ROOT_PATH=
ROOT_PATH="/usr/sbin:/usr/bin:/sbin:/bin:${HOME}/.local/tools/yq"
readonly ROOT_PATH

# 3. Explicit contract-driven environment variable passthrough profile
# Environment variables allowed to pass through sudo
PRESERVE_ENV=
PRESERVE_ENV="$(
  printf "%s," \
    DEBIAN_FRONTEND \
    SRC_ATTIC_CONFIG \
    SRC_ATTIC_SERVICE \
    ATTIC_REF \
    WG_ROOT \
    VERBOSE \
    HOMELAB_DIR \
    ROUTER_ADDR \
    SSH_USER_ROUTER \
    ROUTER_SSH_PORT \
    SSH_OPTS \
    SOPS_AGE_KEY_FILE \
    SOPS \
    SECRETS_FILE \
    STAMP_DIR_ROOT \
    STAMP_DIR_USER \
    STAMP_SALT \
    YQ \
  | sed 's/,$//'
)"
readonly PRESERVE_ENV

# --------------------------------------------------------------------
# BRANCH A — Already root
# --------------------------------------------------------------------
# Replaces the process image immediately. Sanitizes the execution PATH
# to match root defaults.
# --------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
	export PATH="$ROOT_PATH"
	exec "$@"
fi

# --------------------------------------------------------------------
# BRANCH B — Escalation via sudo
# --------------------------------------------------------------------
# Replaces the process image using sudo. Preserves designated keys
# without forcing non-interactive failure mode (-n is omitted).
# --------------------------------------------------------------------
if command -v sudo >/dev/null 2>&1; then
	export PATH="$ROOT_PATH"
	exec sudo --preserve-env="$PRESERVE_ENV" -- "$@"
fi

# --------------------------------------------------------------------
# BRANCH C — No valid escalation path
# --------------------------------------------------------------------
# Reached only if execution is non-privileged and sudo is missing.
# Fallbacks utilizing single-string interpolation ($*) are banned.
# --------------------------------------------------------------------
echo "run-as-root: cannot escalate to root (sudo not found and not running as root)" >&2
exit 69