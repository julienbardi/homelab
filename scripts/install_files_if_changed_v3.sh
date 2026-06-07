#!/bin/sh
# install_files_if_changed_v3.sh — vectorized IFC v3 (slow‑path only, POSIX)

set -u
LC_ALL=C; export LC_ALL

VAR_NAME="$1"
shift

# Validate argument count
if [ "$#" -eq 0 ] || [ $(( $# % 9 )) -ne 0 ]; then
    echo "❌ IFCv3-vector: argument count not divisible by 9" >&2
    exit 1
fi

log() {
    echo "$*" >&2
}

# --- 1. Slow-path: per-file IFC v3 only ---
changed=0

# Work on the current $@ once; no reuse
while [ "$#" -gt 0 ]; do
    SRC_HOST="$1"
    SRC_PORT="$2"
    SRC_PATH="$3"
    DST_HOST="$4"
    DST_PORT="$5"
    DST_PATH="$6"
    OWNER="$7"
    GROUP="$8"
    MODE="$9"

    rc=0
    install_file_if_changed_v3.sh \
        "$SRC_HOST" "$SRC_PORT" "$SRC_PATH" \
        "$DST_HOST" "$DST_PORT" "$DST_PATH" \
        "$OWNER" "$GROUP" "$MODE" || rc=$?

    if [ "$rc" -eq 3 ]; then
        changed=1
    elif [ "$rc" -ne 0 ]; then
        echo "❌ IFCv3-vector: failed for $DST_PATH (rc=$rc)" >&2
        exit "$rc"
    fi

    shift 9
done

if [ "$changed" -eq 1 ]; then
    eval "$VAR_NAME=1"
    exit 3
fi

eval "$VAR_NAME=0"
exit 0
