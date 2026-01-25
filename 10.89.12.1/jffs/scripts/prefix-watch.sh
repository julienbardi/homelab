#!/bin/sh
OUT=/tmp/prefix-last
CUR="$(ip -6 route show | awk '/^[0-9a-f]/ {print $1; exit}')"
PREV="$(cat ${OUT} 2>/dev/null || true)"
if [ -n "$PREV" ] && [ "$PREV" != "$CUR" ]; then
  logger -t ddns-health "IPv6 delegated prefix changed: ${PREV} -> ${CUR}"
fi
echo "$CUR" > "${OUT}"
