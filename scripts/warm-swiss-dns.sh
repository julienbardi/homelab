#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuration
RESOLVER="${1:-127.0.0.1}"     # resolver IP
COUNT="${2:-50}"              # how many top sites to fetch
PARALLEL="${3:-20}"           # parallel dig workers
TMPDIR="$(mktemp -d)"
SIMILARWEB_URL="https://www.similarweb.com/top-websites/switzerland/"
OUT_LIST="${TMPDIR}/swiss-top.txt"

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Fetch and parse Similarweb public page
fetch_similarweb() {
		log "Fetching top sites from Similarweb..."
		if command -v pup >/dev/null 2>&1; then
				curl -fsSL "$SIMILARWEB_URL" \
						| pup 'a.topListItem__titleText text{}' \
						| sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' \
						| sed -E 's/^www\.//' \
						| awk 'NF' \
						| head -n "$COUNT" > "$OUT_LIST"
				return 0
		fi

		# Fallback HTML parsing (best-effort)
		if curl -fsSL "$SIMILARWEB_URL" > "${TMPDIR}/sw.html"; then
				grep -oP '(?<=<a[^>]*class="topListItem__titleText"[^>]*>)[^<]+' "${TMPDIR}/sw.html" \
						| sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' \
						| sed -E 's/^www\.//' \
						| awk 'NF' \
						| head -n "$COUNT" > "$OUT_LIST"
				[ -s "$OUT_LIST" ] && return 0
		fi

		return 1
}

# Built-in fallback list
write_fallback() {
		log "Using built-in fallback domain list"
		cat > "$OUT_LIST" <<'EOF'
srf.ch
20min.ch
blick.ch
galaxus.ch
ricardo.ch
admin.ch
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
facebook.com
wikipedia.org
EOF
}

# Normalize and deduplicate domain list
sanitize_list() {
		awk '{print tolower($0)}' "$OUT_LIST" \
				| sed -E 's#^https?://##; s#/.*$##; s/^www\.//' \
				| awk 'NF' \
				| awk '!seen[$0]++' > "${OUT_LIST}.sanitized"
		mv "${OUT_LIST}.sanitized" "$OUT_LIST"
}

# Warm DNS cache
warm_cache() {
		log "Warming resolver ${RESOLVER} with $(wc -l < "$OUT_LIST") domains (parallel=${PARALLEL})"
		export RESOLVER

		xargs -a "$OUT_LIST" -P "$PARALLEL" -I{} bash -c '
				d="{}"
				dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" A     >/dev/null 2>&1 || true
				dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" AAAA  >/dev/null 2>&1 || true
				dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" NS    >/dev/null 2>&1 || true
		'
		log "Warming complete"
}

# Main
if fetch_similarweb; then
		log "Fetched top sites from Similarweb"
else
		write_fallback
fi

sanitize_list

log "Final domain count: $(wc -l < "$OUT_LIST")"
log "Sample domains:"
head -n 20 "$OUT_LIST" | sed 's/^/  - /' >&2

warm_cache

log "Verification (first 10):"
head -n 10 "$OUT_LIST" | while read -r d; do
		printf '  %s -> ' "$d"
		dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" A \
				| awk 'NF{print $1" "$5; exit}' || echo "no A"
done
