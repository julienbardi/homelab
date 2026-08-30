#!/bin/sh
# dnsmasq-ready.sh

for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pidof dnsmasq >/dev/null 2>&1; then
        echo "… dnsmasq not running (attempt $i)"
        sleep 1
        continue
    fi

    # Functional query validation (checking stdout for expected router IP)
    DNS_OUTPUT="$(nslookup router.lan.bardi.ch 10.89.12.1 2>/dev/null)"
    if echo "$DNS_OUTPUT" | grep -q "10.89.12.1"; then
        echo "🟢 dnsmasq is ready"
        exit 0
    fi

    echo "… dnsmasq not yet authoritative (attempt $i)"
    sleep 1
done

echo "❌ dnsmasq did not become ready in time"
exit 1