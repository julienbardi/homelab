#!/bin/bash
set -eo pipefail
set +u

# Always retrieve IPv6 prefix from router
ipv6_prefix=""
for i in 1 2 3; do
    ipv6_prefix="$(ssh -p "$ROUTER_SSH_PORT" "$ROUTER_USER@$ROUTER_ADDR" 'nvram get ipv6_prefix' 2>/dev/null || true)"
    [[ -n "$ipv6_prefix" ]] && break
    sleep 0.2
done

ipv6_prefix="$(echo "$ipv6_prefix" | tr -d '[:space:]')"

if [[ -n "$ipv6_prefix" ]]; then
    router6_ip="${ipv6_prefix}1"
else
    router6_ip=""
fi

#echo "prefix=[$ipv6_prefix] router6_ip=[$router6_ip]"

RESOLVERS=(
  "loopback4:127.0.0.1"
  "loopback6:::1"
  "nas4:${LAN_NAS}"
  "nas6:${LAN6_NAS}"
  "router4:${LAN_ROUTER}"
)

# Dynamic WAN IPv6 prefix from router
if [[ -n "$router6_ip" ]]; then
    RESOLVERS+=("router6_wan:$router6_ip")
fi


tmpdir="$(mktemp -d "$HOME/.local/state/homelab/dns-suite.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

echo "🚀 Running DNS suite in parallel…"

# Pre-authenticate sudo so background jobs don't fail
sudo -v

for entry in "${RESOLVERS[@]}"; do
  name="${entry%%:*}"
  ip="${entry#*:}"

  (
    out="$(sudo /usr/local/bin/dns-health-check.sh "$ip" 2>&1 || true)"
    echo "$out" >"$tmpdir/$name.out"

    if grep -q "DNS recursion and DNSSEC enforcement are working correctly" <<<"$out"; then
      echo OK >"$tmpdir/$name.status"
    else
      echo FAIL >"$tmpdir/$name.status"
    fi
  ) &
done

wait

echo
echo "📊 DNS Suite Results"
echo "---------------------"

overall_ok=true

for entry in "${RESOLVERS[@]}"; do
  name="${entry%%:*}"
  status=$(cat "$tmpdir/$name.status")

  if [[ "$status" == "OK" ]]; then
    echo "✅ $name"
  else
    echo "❌ $name"
    overall_ok=false
  fi

  if [[ "${VERBOSE:-0}" == "1" ]]; then
    echo
    echo "----- $name output -----"
    cat "$tmpdir/$name.out"
    echo "------------------------"
    echo
  fi
done

echo
$overall_ok && { echo "🎉 All resolvers healthy"; exit 0; }
echo "❌ One or more resolvers failed"
exit 1
