#!/bin/sh
set -eu
# ensure_dir.sh
# Idempotently ensure a directory exists with given owner/group/mode.
# Escalates only if required (sudo/doas).
#
# Usage:
#   ensure_dir.sh OWNER GROUP MODE PATH

[ "$#" -eq 4 ] || {
    echo "usage: $0 OWNER GROUP MODE PATH" >&2
    exit 64
}

owner="$1"
group="$2"
mode="$3"
path="$4"

if [ -d "$path" ]; then
    current="$(stat -c '%U:%G:%a' "$path" 2>/dev/null || true)"
    expected="$owner:$group:$mode"
    [ "$current" = "$expected" ] && exit 0
fi

# Try without escalation first
if install -d -o "$owner" -g "$group" -m "$mode" "$path" 2>/dev/null; then
    exit 0
fi

# Escalate explicitly
if command -v sudo >/dev/null 2>&1; then
    exec sudo install -d -o "$owner" -g "$group" -m "$mode" "$path"
elif command -v doas >/dev/null 2>&1; then
    exec doas install -d -o "$owner" -g "$group" -m "$mode" "$path"
else
    echo "🚫 ensure_dir: cannot create $path (no sudo/doas available)" >&2
    exit 77
fi
