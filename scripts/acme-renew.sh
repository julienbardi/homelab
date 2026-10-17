#!/bin/sh
# ------------------------------------------------------------------
# scripts/acme-renew.sh
#
# CONTRACT:
# - Renews existing ACME certificate lineages
# - Assumes ACME lineage state already exists
# - Does NOT perform first issuance itself
# - Does NOT modify SAN sets
# - Renews all registered certificate families via acme.sh --cron
# - Safe to run repeatedly
#
# Expected ACME certificate lineages:
#     bardi.ch_ecc
#     bardi.ch_rsa
#
# NOTE:
# - The Make target may establish issuance prerequisites before
#   invoking this script.
# - This script itself performs renewal only.
# ------------------------------------------------------------------

set -eu

ACME_HOME="/var/lib/acme"

exec "$ACME_HOME/acme.sh" \
    --cron \
    --debug 2 \
    --home "$ACME_HOME"