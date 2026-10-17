#!/bin/sh
# ------------------------------------------------------------------
# scripts/acme-renew.sh
#
# CONTRACT:
# - Renews existing ACME certificate lineages only
# - Assumes ACME lineage state already exists
# - Does NOT perform first issuance itself
# - Does NOT modify SAN sets
# - Does NOT create new lineages
# - Fails if a required lineage is missing
# - Renews all registered certificate families via acme.sh --cron
# - Safe to run repeatedly
#
# Required ACME certificate lineages:
#     bardi.ch
#     bardi.ch_ecc
#
# NOTE:
# - Issuance belongs in acme-issue.sh
# - Renewal belongs in acme-renew.sh
# - Missing lineages are considered an operator error
# ------------------------------------------------------------------

set -eu

ACME_HOME="/var/lib/acme"

ECC_LINEAGE="$ACME_HOME/bardi.ch_ecc"
RSA_LINEAGE="$ACME_HOME/bardi.ch"

ECC_CERT="$ECC_LINEAGE/fullchain.cer"
RSA_CERT="$RSA_LINEAGE/fullchain.cer"

# ------------------------------------------------------------------
# Contract validation
# ------------------------------------------------------------------

echo "🔍 validating $ECC_CERT"

[ -f "$ECC_CERT" ] || {
	echo "❌ missing ECC lineage: $ECC_CERT" >&2
	exit 1
}

echo "🔍 validating $RSA_CERT"

[ -f "$RSA_CERT" ] || {
	echo "❌ missing RSA lineage: $RSA_CERT" >&2
	exit 1
}

# ------------------------------------------------------------------
# Renewal
#
# acme.sh decides internally whether renewal is required.
# Existing lineages only.
# ------------------------------------------------------------------

exec "$ACME_HOME/acme.sh" \
	--cron \
	--home "$ACME_HOME"
