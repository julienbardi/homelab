#!/bin/sh
# acme-issue-if-needed.sh
ACME_HOME="/var/lib/acme"
PRIMARY_DOMAIN="${DOMAIN:-bardi.ch}"

# ECC first-issue
if [ ! -d "$ACME_HOME/${PRIMARY_DOMAIN}_ecc" ]; then
    exec "$ACME_HOME/acme.sh" \
        --issue \
        --dns dns_infomaniak \
        --home "$ACME_HOME" \
        -d "$PRIMARY_DOMAIN" \
        -d "*.$PRIMARY_DOMAIN"
fi

# RSA first-issue (for DSM only)
if [ ! -d "$ACME_HOME/${PRIMARY_DOMAIN}_rsa" ]; then
    exec "$ACME_HOME/acme.sh" \
        --issue \
        --dns dns_infomaniak \
        --home "$ACME_HOME" \
        --keylength 2048 \
        -d "$PRIMARY_DOMAIN" \
        -d "*.$PRIMARY_DOMAIN"
fi
