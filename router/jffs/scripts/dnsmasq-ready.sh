#!/bin/sh

for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pidof dnsmasq >/dev/null 2>&1; then
        echo "… dnsmasq not running (attempt $i)"
        sleep 1
        continue
    fi

    if ! nc -z -u 10.89.12.1 53 >/dev/null 2>&1; then
        echo "… dnsmasq UDP/53 not ready (attempt $i)"
        sleep 1
        continue
    fi

    if ! nc -z 10.89.12.1 53 >/dev/null 2>&1; then
        echo "… dnsmasq TCP/53 not ready (attempt $i)"
        sleep 1
        continue
    fi

    if nslookup router.lan.bardi.ch 10.89.12.1 >/dev/null 2>&1; then
        echo "🟢 dnsmasq is ready"
        exit 0
    fi

    echo "… dnsmasq answering but not authoritative (attempt $i)"
    sleep 1
done

echo "❌ dnsmasq did not become ready in time"
exit 1
