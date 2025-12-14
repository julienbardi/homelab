#!/usr/bin/env bash
# scripts/dns-warm-rotate.sh
set -euo pipefail
IFS=$'\n\t'

RESOLVER="${1:-127.0.0.1}"
DOMAINS_FILE="/etc/dns-warm/domains_v2.txt"
STATE_FILE="/var/lib/dns-warm/state_v2.csv"
CSV_URL="https://portal.switch.ch/open-data/top1000/latest.csv"

WORKERS=2
PER_RUN=1000   # warm all domains in one run
DIG_TIMEOUT=5
DIG_TRIES=3
LOCKFILE="/var/lock/dns-warm-rotate_v2.lock"

mkdir -p "$(dirname "$STATE_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

fetch_domains() {
	curl -s "$CSV_URL" | awk -F, 'NR>1 {print $1}' > "$DOMAINS_FILE"
	chmod 644 "$DOMAINS_FILE"
}

init_state() {
	if [ ! -f "$STATE_FILE" ]; then
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			printf '%s,0\n' "$line"
		done < "$DOMAINS_FILE" > "$STATE_FILE"
		chmod 640 "$STATE_FILE"
		return
	fi

	while IFS= read -r d; do
		[ -z "$d" ] && continue
		if ! awk -F, -v dom="$d" '$1==dom{exit 0} END{exit 1}' "$STATE_FILE"; then
			echo "$d,0" >> "$STATE_FILE"
		fi
	done < "$DOMAINS_FILE"
}

select_oldest() {
	awk -F, '{print $2","$1}' "$STATE_FILE" | sort -n | awk -F, -v n="$PER_RUN" 'NR<=n{print $2}'
}

update_state() {
	local now tmp
	now="$(date +%s)"
	tmp="$(mktemp)"
	while IFS=, read -r dom last; do
		if echo "$1" | grep -qw "$dom"; then
			echo "$dom,$now"
		else
			echo "$dom,$last"
		fi
	done < "$STATE_FILE" > "$tmp"
	mv "$tmp" "$STATE_FILE"
}

# Counters
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
		local now=$(date +%s)
		local elapsed=$((now - start))
		local done=$(<"$COUNTER_DONE")
		local active=$(<"$COUNTER_ACTIVE")
		local remaining=$((total - done - active))

		# ETA = now + 5s per remaining
		local eta_secs=$((now + remaining * 53 / 1000))
		local eta_str=$(date '+%H:%M:%S' -d "@$eta_secs")

	 # throughput = done/elapsed
		local rate="0.00"
		if [ "$elapsed" -gt 0 ]; then
			rate=$(awk -v d="$done" -v e="$elapsed" 'BEGIN{printf "%.2f", d/e}')
		fi

		printf '\rActive: %d workers | Done: %d/%d | start %s | elapsed %ds | ETA %s | rate %s req/s' \
			"$active" "$done" "$total" "$start_str" "$elapsed" "$eta_str" "$rate"

		# stop when all done
		if [ "$done" -ge "$total" ]; then
			printf '\nAll %d domains warmed in %ds | avg rate %.2f req/s\n' \
				"$total" "$elapsed" "$(awk -v d="$done" -v e="$elapsed" 'BEGIN{printf "%.2f", d/e}')"
			break
		fi
	done
}

warm_domain() {
	local d="$1"
	# mark active
	(
		flock -x 201
		local active=$(<"$COUNTER_ACTIVE")
		echo $((active+1)) > "$COUNTER_ACTIVE"
	) 201>"$COUNTER_ACTIVE.lock"

	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" A >/dev/null 2>&1 || true
	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" AAAA >/dev/null 2>&1 || true
	dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" NS >/dev/null 2>&1 || true

	# decrement active, increment done
	(
		flock -x 201
		local active=$(<"$COUNTER_ACTIVE")
		echo $((active-1)) > "$COUNTER_ACTIVE"
	) 201>"$COUNTER_ACTIVE.lock"

	(
		flock -x 200
		local done=$(<"$COUNTER_DONE")
		echo $((done+1)) > "$COUNTER_DONE"
	) 200>"$COUNTER_DONE.lock"
}

main() {
	exec 9>"$LOCKFILE"
	if ! flock -n 9; then
		log "Another instance is running; exiting"
		exit 0
	fi

	# Always refresh domains from SWITCH CSV
	fetch_domains
	init_state

	tmpfile="$(mktemp)"
	select_oldest > "$tmpfile"
	mapfile -t to_warm < "$tmpfile"
	rm -f "$tmpfile"

	if [ "${#to_warm[@]}" -eq 0 ]; then
		log "No domains to warm"
		exit 0
	fi

	log "Warming ${#to_warm[@]} domains (resolver=${RESOLVER})"

	progress &   # start progress reporter
	progress_pid=$!

	sem=0
	warmed_list=""
	for d in "${to_warm[@]}"; do
		warm_domain "$d" &
		((sem++))
		warmed_list="$warmed_list $d"
		if [ "$sem" -ge "$WORKERS" ]; then
			wait -n || true
			sem=$((sem-1))
		fi
		sleep 0.05   # small delay so progress loop can catch increments
	done

	wait || true
	kill "$progress_pid" 2>/dev/null

	update_state "$warmed_list"
	log "Warming complete; updated state for ${#to_warm[@]} domains"
}

main || true
