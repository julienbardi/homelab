#!/bin/sh
# acme-issue.sh
set -eu

ACME_HOME="/var/lib/acme"
PRIMARY_DOMAIN="${DOMAIN}"

# Issue only if cert directory does not exist
if [ ! -d "$ACME_HOME/${PRIMARY_DOMAIN}_ecc" ]; then
    exec "$ACME_HOME/acme.sh" \
        --issue \
        --dns dns_infomaniak \
        --debug 2 \
        --home "$ACME_HOME" \
        -d "$PRIMARY_DOMAIN" \
        -d "*.$PRIMARY_DOMAIN"
fi
