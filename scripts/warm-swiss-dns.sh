#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuration
RESOLVER="${1:-127.0.0.1}"     # first arg overrides resolver IP
COUNT="${2:-50}"               # how many top sites to fetch (if supported)
PARALLEL="${3:-20}"            # parallel dig workers
TMPDIR="$(mktemp -d)"
SIMILARWEB_URL="https://www.similarweb.com/top-websites/switzerland/"
OUT_LIST="${TMPDIR}/swiss-top.txt"

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Try to fetch and parse Similarweb public page
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

  # Fallback HTML parsing using grep/sed/awk (fragile but often works)
  if curl -fsSL "$SIMILARWEB_URL" > "${TMPDIR}/sw.html"; then
    grep -oP '(?<=<a[^>]*class="topListItem__titleText"[^>]*>)[^<]+' "${TMPDIR}/sw.html" \
      | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//' \
      | sed -E 's/^www\.//' \
      | awk 'NF' \
      | head -n "$COUNT" > "$OUT_LIST"
    # ensure file non-empty
    if [ -s "$OUT_LIST" ]; then
      return 0
    fi
  fi

  return 1
}

# Built-in fallback list (Swiss-focused + global high-traffic)
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

# Sanitize list: remove duplicates, empty lines
sanitize_list() {
  awk '{print tolower($0)}' "$OUT_LIST" \
    | sed -E 's#^https?://##; s#/.*$##; s/^www\.//' \
    | awk 'NF' \
    | awk '!seen[$0]++' > "${OUT_LIST}.sanitized"
  mv "${OUT_LIST}.sanitized" "$OUT_LIST"
}

# Warm function: query A/AAAA/NS for each domain in parallel
warm_cache() {
  log "Warming resolver ${RESOLVER} with $(wc -l < "$OUT_LIST") domains (parallel=${PARALLEL})"
  export RESOLVER
  export TMPDIR
  export -f log

  # Use xargs for parallelism; each job queries A, AAAA, NS
  xargs -a "$OUT_LIST" -n1 -P "$PARALLEL" -I{} bash -c '
    d="{}"
    # Query A, AAAA, NS; ignore failures but keep short timeout
    dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" A >/dev/null 2>&1 || true
    dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" AAAA >/dev/null 2>&1 || true
    dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" NS >/dev/null 2>&1 || true
  ' _
  log "Warming complete"
}

# Main
if fetch_similarweb; then
  log "Fetched top sites from Similarweb -> $OUT_LIST"
else
  write_fallback
fi

sanitize_list

log "Final domain count: $(wc -l < "$OUT_LIST")"
# Optional: show first 20
log "Sample domains:"
head -n 20 "$OUT_LIST" | sed -e 's/^/  - /' | sed -n '1,20p' >&2

warm_cache

# Print a quick verification sample
log "Verification (first 10):"
head -n 10 "$OUT_LIST" | while read -r d; do
  echo -n "  $d -> "
  dig @"$RESOLVER" +time=2 +tries=1 +noall +answer "$d" A | awk 'NF{print $1" "$5; exit}' || echo "no A"
done

