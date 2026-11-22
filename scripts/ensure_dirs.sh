#!/bin/sh

# ensure_dirs.sh
#
# Usage:
#   ensure_dirs.sh PATH OWNER GROUP MODE \
#                  PATH OWNER GROUP MODE \
#                  ...

set -eu

changed=0

if [ $(( $# % 4 )) -ne 0 ]; then
	echo "❌ Usage: PATH OWNER GROUP MODE ..." >&2
	exit 64
fi

while [ "$#" -gt 0 ]; do
	DIR="$1"
	OWNER="$2"
	GROUP="$3"
	MODE="$4"
	shift 4

	# ------------------------------------------------------------
	# Collision detection
	# ------------------------------------------------------------

	if [ -e "$DIR" ] && [ ! -d "$DIR" ]; then
		echo "🚫 ensure_dirs: $DIR exists but is not a directory" >&2
		exit 73
	fi

	# ------------------------------------------------------------
	# Normalize requested mode
	# ------------------------------------------------------------

	norm_mode="${MODE#0}"
	while [ "$norm_mode" != "${norm_mode#0}" ]; do
		norm_mode="${norm_mode#0}"
	done
	[ -n "$norm_mode" ] || norm_mode="0"

	# ------------------------------------------------------------
	# Resolve UID/GID
	# ------------------------------------------------------------

	target_uid=$(id -u "$OWNER" 2>/dev/null || echo "$OWNER")

	target_gid=$(getent group "$GROUP" 2>/dev/null | cut -d: -f3)
	[ -n "$target_gid" ] || target_gid="$GROUP"

	missing=0
	owner_drift=0
	group_drift=0
	mode_drift=0

	if [ ! -d "$DIR" ]; then
		missing=1
	else
		current="$(stat -c '%u:%g:%a' "$DIR" 2>/dev/null || echo '')"

		cur_uid=$(echo "$current" | cut -d: -f1)
		cur_gid=$(echo "$current" | cut -d: -f2)
		cur_mode=$(echo "$current" | cut -d: -f3)

		[ "$cur_uid" = "$target_uid" ] || owner_drift=1
		[ "$cur_gid" = "$target_gid" ] || group_drift=1
		[ "$cur_mode" = "$norm_mode" ] || mode_drift=1
	fi

	if [ "$missing" -eq 1 ] ||
	   [ "$owner_drift" -eq 1 ] ||
	   [ "$group_drift" -eq 1 ] ||
	   [ "$mode_drift" -eq 1 ]; then

		install -d \
			-o "$OWNER" \
			-g "$GROUP" \
			-m "$MODE" \
			"$DIR"

		echo "📁 ensured $DIR (exists:$missing owner:$owner_drift group:$group_drift mode:$mode_drift)"

		changed=1
	fi
done

if [ "$changed" -eq 1 ]; then
	exit 3
fi

exit 0
