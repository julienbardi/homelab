#!/bin/sh
# IFC v4 remote receiver — single SSH, multi-file, atomic installs
set -eu

TMP_ROOT="/jffs/homelab/.ifc_v4"
mkdir -p "$TMP_ROOT"

while :; do
    if ! IFS=' ' read -r cmd dst owner group mode length sha; then
        exit 0
    fi

    [ "$cmd" = "FILE" ] || {
        [ "$cmd" = "END" ] && exit 0
        echo "❌ IFCv4[remote]: unknown cmd: $cmd" >&2
        exit 1
    }

    tmp="$TMP_ROOT/$$.$RANDOM"
    dir=$(dirname "$dst")
    mkdir -p "$dir"

    # Read exactly $length bytes into tmp
    dd bs=1 count="$length" of="$tmp" 2>/dev/null

    # Optional: remote hash check (disabled for now)
    # h=$(sha256sum "$tmp" | awk '{print $1}')
    # [ "$h" = "$sha" ] || { echo "❌ IFCv4[remote]: hash mismatch for $dst" >&2; rm -f "$tmp"; exit 1; }

    chown "$owner:$group" "$tmp" 2>/dev/null || chown "$owner" "$tmp" 2>/dev/null || true
    chmod "$mode" "$tmp" 2>/dev/null || true

    mv -f "$tmp" "$dst" || {
        echo "❌ IFCv4[remote]: move failed for $dst" >&2
        rm -f "$tmp"
        exit 1
    }
done
