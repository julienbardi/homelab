#!/bin/bash
# dnsdist-validate-listeners.sh: Validate that dnsdist is listening on expected interfaces/ports
set -euo pipefail

# Expected plain DNS listeners (IPv6 only)
REQ_PLAIN=(
  "udp [::1]:53"
  "tcp [::1]:53"
)

# Expected DoH listeners (loopback only)
REQ_DOH=(
  "tcp 127.0.0.1:8053"
  "tcp [::1]:8053"
)

fail=0

check_listener() {
  local proto="$1" addrport="$2"
  local pattern
  pattern="$(printf '%s' "$addrport" | sed 's/[][\.^$*+?{}|()]/\\&/g')"

  if ! ss -lntup | grep -qE "${proto}[[:space:]].*${pattern}"; then
    echo "❌ Missing ${proto} listener on ${addrport}"
    fail=1
  else
    echo "✅ ${proto} listener present on ${addrport}"
  fi
}

echo "🔍 Validating dnsdist plain DNS listeners (IPv6 only)"
for spec in "${REQ_PLAIN[@]}"; do
  read -r proto addrport <<<"$spec"
  check_listener "$proto" "$addrport"
done

echo "🔍 Validating dnsdist DoH listeners (loopback)"
for spec in "${REQ_DOH[@]}"; do
  read -r proto addrport <<<"$spec"
  check_listener "$proto" "$addrport"
done

if [ "$fail" -ne 0 ]; then
  echo "❌ dnsdist listener validation failed"
  exit 1
fi

echo "✅ dnsdist listener validation OK"