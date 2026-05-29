#!/bin/bash
# dnsdist-validate-listeners.sh: Validate that dnsdist is listening on expected interfaces/ports
set -euo pipefail

# UGOS invariant:
# - dnsmasq owns IPv4 port 53 (0.0.0.0 + 127.0.0.1)
# - dnsdist owns IPv6 port 53 (::1 + fd89:…::1)
# - dnsdist owns DoH on 127.0.0.1:8053 and ::1:8053

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
  # Escape literal IPv6 brackets and other regex metacharacters
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
