#!/bin/sh
# ------------------------------------------------------------------
# scripts/acme-issue.sh
#
# CONTRACT:
# - Issues missing ACME certificates only
# - Maintains two independent certificate lineages:
#     bardi.ch_ecc
#     bardi.ch_rsa
# - ECC is the canonical homelab certificate
# - RSA exists for DSM compatibility
# - Safe to run repeatedly
# ------------------------------------------------------------------

set -eu

ACME_HOME="/var/lib/acme"
PRIMARY_DOMAIN="${DOMAIN:-bardi.ch}"

# ------------------------------------------------------------------
# ECC certificate (canonical homelab certificate)
# ------------------------------------------------------------------
if [ ! -d "$ACME_HOME/${PRIMARY_DOMAIN}_ecc" ]; then
    "$ACME_HOME/acme.sh" \
        --issue \
        --dns dns_infomaniak \
        --home "$ACME_HOME" \
        -d "$PRIMARY_DOMAIN" \
        -d "*.$PRIMARY_DOMAIN"
fi

# ------------------------------------------------------------------
# RSA certificate (DSM compatibility certificate)
# ------------------------------------------------------------------
if [ ! -d "$ACME_HOME/${PRIMARY_DOMAIN}_rsa" ]; then
    "$ACME_HOME/acme.sh" \
        --issue \
        --dns dns_infomaniak \
        --home "$ACME_HOME" \
        --keylength 2048 \
        -d "$PRIMARY_DOMAIN" \
        -d "*.$PRIMARY_DOMAIN"
fi