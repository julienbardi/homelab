#!/usr/bin/env bash
# scripts/dns-warm-rotate.sh
set -euo pipefail
IFS=$'\n\t'

RESOLVER="${1:-127.0.0.1}"
DOMAINS_FILE="/etc/dns-warm/domains.txt"
STATE_FILE="/var/lib/dns-warm/state.csv"

WORKERS=15
PER_RUN=2400
DIG_TIMEOUT=5
DIG_TRIES=3

LOCKFILE="/var/lib/dns-warm/dns-warm-rotate.lock"

install -d "$(dirname "$DOMAINS_FILE")" "$(dirname "$STATE_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

init_state() {
	if [ -s "$STATE_FILE" ]; then
		return
	fi

	log "Initializing state file from domain policy"
	awk '{print $0 ",0"}' "$DOMAINS_FILE" > "$STATE_FILE"

	if [ ! -s "$STATE_FILE" ]; then
		log "ERROR: failed to initialize state from $DOMAINS_FILE"
		exit 1
	fi

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

	cat > "$warmed_file"

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

	[ -s "$DOMAINS_FILE" ] || {
		log "ERROR: $DOMAINS_FILE missing or empty"
		exit 1
	}

	init_state

	mapfile -t to_warm < <(select_oldest)

	log "Workers: $WORKERS"
	log "Resolver: $RESOLVER"
	log "Domains selected this run: ${#to_warm[@]}"

	progress &
	progress_pid=$!

	sem=0

	for d in "${to_warm[@]}"; do
		warm_domain "$d" &
		((sem++))
		[ "$sem" -ge "$WORKERS" ] && { wait -n || true; sem=$((sem-1)); }
	done

	wait || true
	kill "$progress_pid" 2>/dev/null || true

	printf '%s\n' "${to_warm[@]}" | update_state
	log "Warming complete; updated state for ${#to_warm[@]} domains"
}

main
