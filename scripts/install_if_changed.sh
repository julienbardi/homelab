#!/bin/sh
# install_if_changed.sh — DEPRECATED compatibility wrapper
#
# This script is deprecated.
# Use install_file_if_changed.sh instead.
#
# This wrapper exists only for backward compatibility and will be removed.

set -eu

quiet=0
dry_run=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -q|--quiet)
            quiet=1
            shift
            ;;
        -n|--dry-run)
            dry_run=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "❌ unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

[ "$#" -eq 5 ] || {
    echo "❌ usage: install_if_changed.sh [-q|--quiet] [-n|--dry-run] SRC DST OWNER GROUP MODE" >&2
    exit 1
}

src="$1"
dst="$2"
owner="$3"
group="$4"
mode="$5"

# Emit deprecation warning unless quiet
if [ "$quiet" -eq 0 ] && [ -z "${INSTALL_IF_CHANGED_DEPRECATED_WARNED:-}" ]; then
    echo "⚠️  install_if_changed.sh is deprecated." >&2
    echo "⚠️  Use install_file_if_changed.sh instead." >&2
    export INSTALL_IF_CHANGED_DEPRECATED_WARNED=1
fi

# Dry-run is no longer supported — fail loudly
if [ "$dry_run" -eq 1 ]; then
    echo "❌ --dry-run is no longer supported." >&2
    echo "❌ Use install_file_if_changed.sh directly." >&2
    exit 1
fi

# Resolve the absolute path to the directory containing this script
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Delegate to the new implementation
QUIET_ARG=
[ "$quiet" -eq 1 ] && QUIET_ARG="-q"

exec "$SCRIPT_DIR/install_file_if_changed.sh" $QUIET_ARG \
    "" "" "$src" \
    "" "" "$dst" \
    "$owner" "$group" "$mode"
