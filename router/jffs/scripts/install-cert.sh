#!/bin/sh
# install-cert.sh — root‑privileged atomic certificate installer for router

set -eu

CMD="$1"
SRC="$2"
DST="$3"
OWNER="${4:-root}"
GROUP="${5:-root}"
MODE="${6:-0600}"

case "$CMD" in
  install)
    mkdir -p "$(dirname "$DST")"
    mv -f "$SRC" "$DST"
    chown "$OWNER:$GROUP" "$DST" 2>/dev/null || chown "$OWNER" "$DST"
    chmod "$MODE" "$DST"
    sync
    ;;

  *)
    echo "Usage: install-cert.sh install SRC DST [OWNER GROUP MODE]" >&2
    exit 1
    ;;
esac
