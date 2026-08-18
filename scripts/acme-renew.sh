#!/bin/sh
# acme-renew.sh — daily ACME renewal
set -eu

ACME_HOME="/var/lib/acme"

# acme.sh --cron performs:
#   - renewal if needed
#   - no re-issue
#   - no SAN changes
#   - no destructive operations
#   - respects Infomaniak DNS provider
exec "$ACME_HOME/acme.sh" --cron --debug 2 --home "$ACME_HOME"