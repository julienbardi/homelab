#!/usr/bin/env bash
# scripts/dns-warm-rotate.sh
set -euo pipefail
IFS=$'\n\t'

RESOLVER="${1:-127.0.0.1}"
DOMAINS_FILE="/etc/dns-warm/domains.txt"
STATE_FILE="/var/lib/dns-warm/state.csv"
WORKERS=10
PER_RUN=100
DIG_TIMEOUT=2
DIG_TRIES=1
LOCKFILE="/var/lock/dns-warm-rotate.lock"

mkdir -p "$(dirname "$STATE_FILE")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

if [ ! -f "$DOMAINS_FILE" ]; then
  cat > "$DOMAINS_FILE" <<'DOMS'
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
wikipedia.org
DOMS
  chmod 644 "$DOMAINS_FILE"
fi

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

warm_domain() {
  local d="$1"
  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" A >/dev/null 2>&1 || true
  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" AAAA >/dev/null 2>&1 || true
  dig @"$RESOLVER" +time="$DIG_TIMEOUT" +tries="$DIG_TRIES" +noall +answer "$d" NS >/dev/null 2>&1 || true
}

main() {
  exec 9>"$LOCKFILE"
  if ! flock -n 9; then
	log "Another instance is running; exiting"
	exit 0
  fi

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
  done

  wait || true

  update_state "$warmed_list"
  log "Warming complete; updated state for ${#to_warm[@]} domains"
}

main || true
