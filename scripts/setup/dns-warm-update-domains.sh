#!/usr/bin/env bash
# dns-warm-update-domains.sh
#
# Policy script: populate /etc/dns-warm/domains.txt
# This script decides *which* domains matter.
#
# dns-warm-rotate.sh consumes the resulting file.

set -euo pipefail
IFS=$'\n\t'

DOMAINS_FILE="/etc/dns-warm/domains.txt"
DOMAIN_CACHE_TTL=$((12 * 60 * 60))

SWITCH_CSV_URL="https://portal.switch.ch/open-data/top1000/latest.csv"
TRANCO_URL="https://tranco-list.eu/download/8LPKV/1000000"

log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

install -d "$(dirname "$DOMAINS_FILE")"

now=$(date +%s)

if [ -f "$DOMAINS_FILE" ]; then
	mtime=$(stat -c %Y "$DOMAINS_FILE")
	age=$((now - mtime))
	if [ "$age" -lt "$DOMAIN_CACHE_TTL" ]; then
		log "Using cached domain list (age: $((age / 3600))h)"
		exit 0
	fi
fi

log "Refreshing domain list"

tmp_switch="$(mktemp)"
tmp_tranco="$(mktemp)"
tmp_all="$(mktemp)"

curl -fsSL "$SWITCH_CSV_URL" \
	| awk -F, 'NR>1 {print $1}' > "$tmp_switch"

curl -fsSL "$TRANCO_URL" \
	| awk 'NF {print $1}' > "$tmp_tranco"

awk '!seen[$0]++' \
	<(cat <<'HOT'
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
wikipedia.org
HOT
	) \
	"$tmp_switch" \
	"$tmp_tranco" \
	> "$tmp_all"

install -m 0644 "$tmp_all" "$DOMAINS_FILE"

rm -f "$tmp_switch" "$tmp_tranco" "$tmp_all"

log "Domain list updated: $(wc -l < "$DOMAINS_FILE") entries"
