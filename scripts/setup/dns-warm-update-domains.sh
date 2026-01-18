#!/usr/bin/env bash
# dns-warm-update-domains.sh
#
# Policy script: populate /etc/dns-warm/domains.txt
# Default policy: SMALL, curated, human-relevant domains only.
#
# Optional override:
#   DNS_WARM_PROFILE=full   (explicitly enable large lists)

set -euo pipefail
IFS=$'\n\t'

DOMAINS_FILE="/etc/dns-warm/domains.txt"
DOMAIN_CACHE_TTL=$((0 * 60 * 60)) # seconds

# Use short for the core curated HOT list below or full
PROFILE="${DNS_WARM_PROFILE:-full}"

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

install -d "$(dirname "$DOMAINS_FILE")"

now=$(date +%s)

if [ -s "$DOMAINS_FILE" ]; then
	mtime=$(stat -c %Y "$DOMAINS_FILE")
	age=$((now - mtime))
	if [ "$age" -lt "$DOMAIN_CACHE_TTL" ]; then
		log "Using cached domain list (age: $((age / 3600))h, profile=$PROFILE)"
		exit 0
	fi
fi

log "Refreshing domain list (profile=$PROFILE)"

tmp_all="$(mktemp)"

# ------------------------------------------------------------
# Core curated list (always included)
# ------------------------------------------------------------
cat <<'HOT' > "$tmp_all"
srf.ch
20min.ch
blick.ch
galaxus.ch
ricardo.ch
admin.ch
bardi.ch
jam9.synology.me
sbb.ch
migros.ch
tagesanzeiger.ch
watson.ch
digitec.ch
post.ch
rts.ch
google.ch
google.com
youtube.com
amazon.de
netflix.com
github.com
linkedin.com
spotify.com
ubs.com
wikipedia.org
workspace-zur3.ra.ubs.com
HOT

# ------------------------------------------------------------
# Optional large lists (explicit opt-in only)
# ------------------------------------------------------------
if [ "$PROFILE" = "full" ]; then
	log "Including large external domain lists"

	tmp_switch="$(mktemp)"
	tmp_tranco="$(mktemp)"

	SWITCH_CSV_URL="https://portal.switch.ch/open-data/top1000/latest.csv"
	TRANCO_URL="https://tranco-list.eu/download/8LPKV/1000000"

	curl -fsSL "$SWITCH_CSV_URL" \
		| awk -F, 'NR>1 && $1 {print $1}' >> "$tmp_switch"

	curl -fsSL "$TRANCO_URL" \
	| awk -F, 'NR > 1 && NF >= 2 {
		sub(/\r$/, "", $2);
		print $2;
		if (++n >= 5000) exit
	}' >> "$tmp_tranco" || {
		rc=$?
		[ "$rc" -eq 23 ] || exit "$rc"
	}



	cat "$tmp_switch" "$tmp_tranco" >> "$tmp_all"

	rm -f "$tmp_switch" "$tmp_tranco"
fi

# ------------------------------------------------------------
# Normalize, deduplicate, validate
# ------------------------------------------------------------
awk '!seen[$0]++' "$tmp_all" \
	| grep -E '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' \
	| sort \
	> "$DOMAINS_FILE"

chmod 0644 "$DOMAINS_FILE"
rm -f "$tmp_all"

log "Domain list updated: $(wc -l < "$DOMAINS_FILE") entries"
