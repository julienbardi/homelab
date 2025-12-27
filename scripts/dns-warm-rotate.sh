#!/usr/bin/env bash
# scripts/dns-warm-rotate.sh
set -euo pipefail
IFS=$'\n\t'

RESOLVER="${1:-127.0.0.1}"
DOMAINS_FILE="/etc/dns-warm/domains.txt"
STATE_FILE="/var/lib/dns-warm/state.csv"
SWITCH_CSV_URL="https://portal.switch.ch/open-data/top1000/latest.csv"
TRANCO_URL="https://tranco-list.eu/download/8LPKV/1000000"

WORKERS=15
PER_RUN=2400
DIG_TIMEOUT=5
DIG_TRIES=3
DOMAIN_CACHE_TTL=$((12 * 60 * 60))
LOCKFILE="/var/lib/dns-warm/dns-warm-rotate.lock"

install -d "$(dirname "$DOMAINS_FILE")" "$(dirname "$STATE_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

fetch_domains() {
	local now mtime age
	now=$(date +%s)

	if [ -f "$DOMAINS_FILE" ]; then
		mtime=$(stat -c %Y "$DOMAINS_FILE")
		age=$((now - mtime))
		if [ "$age" -lt "$DOMAIN_CACHE_TTL" ]; then
			log "Using cached domain list (age: $((age / 3600))h)"
			return
		fi
	fi

	log "Refreshing domain list (cache expired)"

	local tmp_switch tmp_tranco tmp_all
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

	mv "$tmp_all" "$DOMAINS_FILE"
	chmod 644 "$DOMAINS_FILE"
	rm -f "$tmp_switch" "$tmp_tranco"
}

init_state() {
	[ -f "$STATE_FILE" ] && return
	log "Initializing state file (one-time operation)"
	awk '{print $0 ",0"}' "$DOMAINS_FILE" > "$STATE_FILE"
	chmod 640 "$STATE_FILE"
}

select_oldest() {
	awk -F, '{print $2","$1}' "$STATE_FILE" \
	| sort -n \
	| awk -F, -v n="$PER_RUN" 'NR<=n {print $2}'
}

update_state() {
	local now tmp warmed_file
	now="$(date +%s)"
	tmp="$(mktemp)"
	warmed_file="$(mktemp)"

	printf '%s\n' $1 > "$warmed_file"

	awk -F, -v now="$now" -v warmed="$warmed_file" '
		BEGIN { while ((getline < warmed) > 0) w[$1]=1 }
		{ if ($1 in w) print $1 "," now; else print }
	' "$STATE_FILE" > "$tmp"

	mv "$tmp" "$STATE_FILE"
	rm -f "$warmed_file"
}

COUNTER_DONE="$(mktemp)"
COUNTER_ACTIVE="$(mktemp)"
echo 0 > "$COUNTER_DONE"
echo 0 > "$COUNTER_ACTIVE"

progress() {
	local start=$(date +%s)
	local total=${#to_warm[@]}
	local start_str=$(date '+%Y-%m-%d %H:%M:%S')

	while true; do
		sleep 1
		local now elapsed done active rate
		now=$(date +%s)
		elapsed=$((now - start))
		done=$(cat "$COUNTER_DONE")
		active=$(cat "$COUNTER_ACTIVE")

		rate="0.00"
		[ "$elapsed" -gt 0 ] && rate=$(awk -v d="$done" -v e="$elapsed" 'BEGIN{printf "%.2f", d/e}')

		printf '\rActive: %d | Done: %d/%d | start %s | elapsed %ds | rate %s req/s' \
			"$active" "$done" "$total" "$start_str" "$elapsed" "$rate"

		[ "$done" -ge "$total" ] && { printf '\n'; break; }
	done
}

warm_domain() {
	local d="$1"

	(
		flock -x 201
		echo $(( $(<"$COUNTER_ACTIVE") + 1 )) > "$COUNTER_ACTIVE"
	) 201>"$COUNTER_ACTIVE.lock"

	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" A >/dev/null 2>&1 || true
	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" AAAA >/dev/null 2>&1 || true
	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" NS >/dev/null 2>&1 || true

	(
		flock -x 201
		echo $(( $(<"$COUNTER_ACTIVE") - 1 )) > "$COUNTER_ACTIVE"
	) 201>"$COUNTER_ACTIVE.lock"

	(
		flock -x 200
		echo $(( $(<"$COUNTER_DONE") + 1 )) > "$COUNTER_DONE"
	) 200>"$COUNTER_DONE.lock"
}

main() {
	exec 9>"$LOCKFILE"
	flock -n 9 || { log "Another instance is running; exiting"; exit 0; }

	fetch_domains
	init_state

	mapfile -t to_warm < <(select_oldest)

	log "Workers: $WORKERS"
	log "Resolver: $RESOLVER"
	log "Domains selected this run: ${#to_warm[@]}"

	progress &
	progress_pid=$!

	sem=0
	warmed_list=""

	for d in "${to_warm[@]}"; do
		warm_domain "$d" &
		((sem++))
		warmed_list="$warmed_list $d"

		[ "$sem" -ge "$WORKERS" ] && { wait -n || true; sem=$((sem-1)); }
	done

	wait || true
	kill "$progress_pid" 2>/dev/null

	update_state "$warmed_list"
	log "Warming complete; updated state for ${#to_warm[@]} domains"
}

main || true
