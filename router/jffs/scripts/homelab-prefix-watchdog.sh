#!/bin/sh

CURRENT=$(ip -6 addr show dev eth0 | grep "scope global" | awk '{print $2}' | cut -d/ -f1)
ROUTER=$(ssh julie@10.89.12.1 -p 2222 "ip -6 addr show dev br0 | grep 'scope global' | awk '{print \$2}' | cut -d/ -f1")

if [ -z "$CURRENT" ] || [ -z "$ROUTER" ]; then
    exit 0
fi

PREFIX_CURRENT=$(echo $CURRENT | cut -d: -f1-4)
PREFIX_ROUTER=$(echo $ROUTER | cut -d: -f1-4)

if [ "$PREFIX_CURRENT" != "$PREFIX_ROUTER" ]; then
    echo "IPv6 prefix drift detected — refreshing RA"
    systemctl restart networking || systemctl restart systemd-networkd
fi
