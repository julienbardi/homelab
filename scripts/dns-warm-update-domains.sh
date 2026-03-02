#!/usr/bin/env bash
# dns-warm-update-domains.sh
#
# Policy script: populate /etc/dns-warm/domains.txt
# Default policy: SMALL, curated, human-relevant domains only.
#
# Optional override:
#   DNS_WARM_PROFILE=full   (explicitly enable large lists)

set -euo pipefail
source "/home/julie/src/homelab/scripts/common.sh"

require_bin funzip "Tranco list extraction"
require_bin curl "Domain list downloads"
require_bin awk "List processing"

IFS=$'\n\t'

DOMAINS_FILE="/etc/dns-warm/domains.txt"
DOMAIN_CACHE_TTL="${DNS_WARM_CACHE_TTL:-3600}"
TRANCO_LIMIT="${DNS_WARM_TRANCO_LIMIT:-100000}"

CURATED_FILE="/etc/dns-warm/curated.txt"

# Profile controls inclusion of large external lists
PROFILE="${DNS_WARM_PROFILE:-full}"

[ "$(id -u)" -eq 0 ] || {
	log "❌ must be run as root"
	exit 1
}

[ "$DOMAIN_CACHE_TTL" -eq 0 ] && log "Cache disabled (TTL=0)"

install -d "$(dirname "$DOMAINS_FILE")"

now=$(date +%s)

if [ -s "$DOMAINS_FILE" ]; then
	mtime=$(stat -c %Y "$DOMAINS_FILE")
	age=$((now - mtime))
	if [ "$age" -lt "$DOMAIN_CACHE_TTL" ]; then
		log "Using cached domain list (age: $((age))s, profile=$PROFILE)"
		exit 0
	fi
fi

log "Refreshing domain list (profile=$PROFILE)"

# Initialize variables to ensure trap safety
tmp_all="$(mktemp)"
tmp_final="$(mktemp)"
trap 'rm -f "$tmp_all" "$tmp_final" "${tmp_switch:-}" "${tmp_tranco:-}"' EXIT

if [ ! -f "$CURATED_FILE" ]; then
	log "Creating empty curated list at $CURATED_FILE"
	install -m 0644 /dev/null "$CURATED_FILE"
fi


cat "$CURATED_FILE" > "$tmp_all"

# ------------------------------------------------------------
# Optional large lists (explicit opt-in only)
# ------------------------------------------------------------
if [ "$PROFILE" = "full" ]; then
log "Including large external domain lists"

	tmp_switch="$(mktemp)"
	tmp_tranco="$(mktemp)"

	SWITCH_CSV_URL="https://portal.switch.ch/open-data/top1000/latest.csv"
	TRANCO_URL="https://tranco-list.eu/top-1m.csv.zip"

	# 1. Fetch SWITCH list
	if ! curl -fsSL "$SWITCH_CSV_URL" | awk -F, 'NR>1 && $1 {print $1}' >> "$tmp_switch"; then
		log "❌ SWITCH domain list unavailable"
		exit 1
	fi

	# 2. Fetch Tranco list with SIGPIPE handling
	set +o pipefail
	curl -fsSL "$TRANCO_URL" | funzip | \
		awk -F, -v limit="$TRANCO_LIMIT" 'NR > 1 && NF >= 2 {
			sub(/\r$/, "", $2);
			print $2;
			if (++n >= limit) exit
		}' >> "$tmp_tranco"
	rc=$?
	set -o pipefail

	# rc 141 is SIGPIPE; it means we hit our limit and awk closed the pipe. This is a SUCCESS.
	if [ "$rc" -eq 0 ] || [ "$rc" -eq 141 ]; then
		log "✅ External lists fetched (limit: $TRANCO_LIMIT)"
	else
		log "❌ Tranco download failed (rc=$rc)"
		exit 1
	fi

	cat "$tmp_switch" "$tmp_tranco" >> "$tmp_all"

	rm -f "$tmp_switch" "$tmp_tranco"
fi

# ------------------------------------------------------------
# Normalize, deduplicate, validate
# ------------------------------------------------------------
grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' "$tmp_all" | sort -u > "$tmp_final"

# Atomic and idempotent installation using common.sh helper
# atomic_install <src> <dest> <owner:group> <mode>
result=$(atomic_install "$tmp_final" "$DOMAINS_FILE" "root:root" "0644")

rm -f "$tmp_all" "$tmp_final"

if [[ "$result" == "changed" ]]; then
	log "✅ Domain list updated: $(wc -l < "$DOMAINS_FILE") entries"
else
	log "⚪ Domain list unchanged: $(wc -l < "$DOMAINS_FILE") entries"
fi
