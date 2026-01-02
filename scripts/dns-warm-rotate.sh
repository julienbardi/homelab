#!/usr/bin/env bash
# scripts/dns-warm-rotate.sh
# to deploy, use
#   make dns-warm-install
set -euo pipefail

# ----------------------------
# Configuration
# ----------------------------
DOMAINS_FILE="/etc/dns-warm/domains.txt"
STATE_FILE="/var/lib/dns-warm/state.csv"
PER_RUN=10000
WORKERS=10      # legacy only
RESOLVER="127.0.0.1"

DNSMASQ_CONF_DIR="/usr/ugreen/etc/dnsmasq/dnsmasq.d"
DNS_FORWARD_MAX=$(grep -Rhs '^dns-forward-max=' "$DNSMASQ_CONF_DIR" | tail -n1 | cut -d= -f2)
DNS_FORWARD_MAX=${DNS_FORWARD_MAX:-default}

# ----------------------------
# Logging
# ----------------------------
log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# ----------------------------
# State initialization
# ----------------------------
init_state() {
	if [ -s "$STATE_FILE" ]; then
		return
	fi

	if [ ! -s "$DOMAINS_FILE" ]; then
		log "dns-warm ERROR: domain policy file missing or empty"
		exit 1
	fi

	awk '{print $0 ",0"}' "$DOMAINS_FILE" >"$STATE_FILE"
	chmod 640 "$STATE_FILE"
}

# ----------------------------
# Domain selection
# ----------------------------
select_oldest() {
	sort -t, -k2,2n "$STATE_FILE" 2>/dev/null | head -n "$PER_RUN" | cut -d, -f1
}

# ----------------------------
# Main
# ----------------------------
main() {
	start_ts=$(date +%s)

	init_state
	mapfile -t DOMAINS < <(select_oldest)

	if [ "${#DOMAINS[@]}" -eq 0 ]; then
		log "dns-warm: domains=0 (nothing to do)"
		exit 0
	fi

	if command -v dns-warm-async >/dev/null; then
		tmpfile=$(mktemp)
		printf '%s\n' "${DOMAINS[@]}" >"$tmpfile"
		/usr/local/bin/dns-warm-async "$tmpfile" >/dev/null
		rm -f "$tmpfile"
	else
		printf '%s\n' "${DOMAINS[@]}" |
			xargs -P"$WORKERS" -I{} \
				dig @"$RESOLVER" {} +timeout=1 +tries=1 >/dev/null || true
	fi

	now=$(date +%s)
	awk -F, -v now="$now" '
		BEGIN { OFS="," }
		NR==FNR { warmed[$1]=1; next }
		{
			if ($1 in warmed) print $1, now
			else print
		}
	' <(printf '%s\n' "${DOMAINS[@]}") "$STATE_FILE" >"$STATE_FILE.tmp"

	mv "$STATE_FILE.tmp" "$STATE_FILE"

	end_ts=$(date +%s)
	duration=$(awk "BEGIN { printf \"%.1f\", $end_ts - $start_ts }")

	if command -v dns-warm-async >/dev/null; then
		log "dns-warm-async: resolver=$RESOLVER domains=${#DOMAINS[@]} duration=${duration}s"
	else
		log "dns-warm: workers=$WORKERS resolver=$RESOLVER domains=${#DOMAINS[@]} dns-forward-max=$DNS_FORWARD_MAX duration=${duration}s"
	fi
}

main "$@"
