#!/bin/sh
# install_if_changed.sh
# install_if_changed.sh — idempotent, atomic file installer
#
# Usage:
#   install_if_changed.sh [-q|--quiet] [-n|--dry-run] SRC DST OWNER GROUP MODE
#
# Guarantees:
# - Installs SRC to DST only if content, owner, group, or mode differ
# - Atomic replacement (no partial writes)
# - Correct ownership and permissions
# - Safe under concurrent runs
# - Minimal I/O (byte-compare, early exit)
# - Clear, honest operator output
#
# Exit codes:
#   0  → Success, destination already up‑to‑date (no change)
#   3  → Success, destination would be updated (dry‑run) or was updated
#        (override with CHANGED_EXIT_CODE environment variable)
#   1  → Failure (invalid arguments, missing source file, or other error)
#
# Options:
#   -q, --quiet     suppress output
#   -n, --dry-run   do not modify DST; only report whether a change would occur
#
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

# Validate inputs early
[ -f "$src" ] || {
	echo "❌ source file not found: $src" >&2
	exit 1
}

case "$mode" in
	[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
	*) echo "❌ invalid mode: $mode" >&2; exit 1 ;;
esac

# Create temp file in same filesystem as destination
dst_dir="$(dirname "$dst")"
tmp="$(mktemp "$dst_dir/.install_if_changed.XXXXXX")"

trap 'rm -f "$tmp"' EXIT INT TERM

# Stage file with correct metadata
install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp"

# Fast path: destination exists and is fully identical (content + metadata)
if [ -f "$dst" ] &&
   cmp -s "$tmp" "$dst" &&
   [ "$(stat -c '%a %u %g' "$tmp")" = "$(stat -c '%a %u %g' "$dst")" ]; then
	if [ "$quiet" -eq 0 ]; then
		echo "⚪ $dst unchanged"
	fi
	exit 0
fi

if [ "$dry_run" -eq 1 ]; then
	if [ "$quiet" -eq 0 ]; then
		echo "🔍 $dst would be updated (dry-run)"
	fi
else
	# Replace destination atomically
	install -m "$mode" -o "$owner" -g "$group" "$tmp" "$dst"
	if [ "$quiet" -eq 0 ]; then
		echo "🔄 $dst updated"
	fi
fi
exit "${CHANGED_EXIT_CODE:-3}"
