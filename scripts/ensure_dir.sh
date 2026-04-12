#!/bin/sh
set -eu

# ensure_dir.sh
# Idempotently ensure a directory exists with given owner/group/mode.

[ "$#" -eq 4 ] || {
    echo "usage: $0 OWNER GROUP MODE PATH" >&2
    exit 64
}

owner="$1"
group="$2"
mode="$3"
path="$4"

# 1. Collision Check
if [ -e "$path" ] && [ ! -d "$path" ]; then
    echo "🚫 ensure_dir: $path exists but is not a directory" >&2
    exit 73
fi

# Normalize mode: strip ALL leading zeros to match 'stat -c %a'
norm_mode="${mode##0}"
[ -z "$norm_mode" ] && norm_mode="0"

# 2. Fast path / Idempotency check
# Only -x is required to stat the metadata
if [ -d "$path" ] && [ -x "$path" ]; then
    current="$(stat -c '%u:%g:%a' "$path" 2>/dev/null || true)"

    # Resolve UID/GID safely
    target_uid=$(id -u "$owner" 2>/dev/null || echo "$owner")

    # Resolve GID: try getent, but fallback to the input string if lookup fails
    target_gid=$(getent group "$group" 2>/dev/null | cut -d: -f3)
    [ -z "$target_gid" ] && target_gid="$group"

    if [ "$current" = "$target_uid:$target_gid:$norm_mode" ]; then
        exit 0
    fi
fi

# 3. Try unprivileged creation/fix first
if install -d -o "$owner" -g "$group" -m "$mode" "$path" 2>/dev/null; then
    exit 0
fi

# 4. Escalate explicitly
if command -v sudo >/dev/null 2>&1; then
    exec sudo install -d -o "$owner" -g "$group" -m "$mode" "$path"
elif command -v doas >/dev/null 2>&1; then
    exec doas install -d -o "$owner" -g "$group" -m "$mode" "$path"
else
    echo "🚫 ensure_dir: cannot create $path (no sudo/doas available)" >&2
    exit 77
fi
