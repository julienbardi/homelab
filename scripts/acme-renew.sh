#!/bin/sh
# ------------------------------------------------------------------
# scripts/acme-renew.sh
#
# CONTRACT:
# - Renews existing ACME certificate lineages
# - Does NOT perform first issuance
# - Does NOT modify SAN sets
# - Renews all registered certificate families
# - Expected certificate lineages:
#     bardi.ch_ecc
#     bardi.ch_rsa
# - Safe to run repeatedly
# ------------------------------------------------------------------

set -eu

ACME_HOME="/var/lib/acme"

exec "$ACME_HOME/acme.sh" \
    --cron \
    --debug 2 \
    --home "$ACME_HOME"