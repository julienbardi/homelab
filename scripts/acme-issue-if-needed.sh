#!/bin/sh
if [ ! -d /var/lib/acme/bardi.ch_ecc ]; then
    exec /var/lib/acme/acme.sh \
        --issue \
        --dns dns_infomaniak \
        --home /var/lib/acme \
        -d bardi.ch \
        -d "*.bardi.ch"
fi
