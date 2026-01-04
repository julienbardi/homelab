#!/usr/bin/env bash
set -euo pipefail

REGISTRY="/volume1/homelab/security/compromised_keys.tsv"
WG_DIR="/etc/wireguard"

mkdir -p "$(dirname "$REGISTRY")"

# Create registry with header if missing (explicit TSV)
if [ ! -f "$REGISTRY" ]; then
	cat >"$REGISTRY" <<'EOF'
# --------------------------------------------------------------------
# Compromised cryptographic material registry
#
# APPEND-ONLY — MACHINE-READABLE — AUDIT-ORIENTED
#
# Columns:
#   type                wireguard | ssh | tls | other
#   compromised_key     public key or stable fingerprint
#   internal_reference  SSH key comment OR WireGuard config name
#   since_utc           ISO-8601 UTC timestamp
#   reason              free-text
# --------------------------------------------------------------------
type    compromised_key internal_reference  since_utc   reason
EOF
	chmod 600 "$REGISTRY"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Recording compromised WireGuard keys"

for pub in "$WG_DIR"/wg*.pub; do
	[ -e "$pub" ] || continue

	iface="$(basename "$pub" .pub)"

	# Stable fingerprint = hash of public key file
	fp="$(sha256sum "$pub" | awk '{print "SHA256:"$1}')"

	# Idempotence: skip if already recorded
	grep -qF "$fp" "$REGISTRY" && continue

	printf "%s\t%s\t%s\t%s\t%s\n" \
		"wireguard" \
		"$fp" \
		"$iface" \
		"$now" \
		"wg-rebuild-all" \
	>>"$REGISTRY"
done

echo "Compromised keys recorded in $REGISTRY"
