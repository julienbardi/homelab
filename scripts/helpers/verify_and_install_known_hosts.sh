#!/usr/bin/env bash
set -euo pipefail

HOSTS_FILE="${1:-known_hosts_to_check.txt}"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M)"
HOSTSCAN_TIMEOUT=5

if [ ! -f "$HOSTS_FILE" ]; then
  echo "Hosts file not found: $HOSTS_FILE" >&2
  exit 2
fi

mkdir -p "$HOME/.ssh"
if [ -f "$HOME/.ssh/known_hosts" ]; then
  cp -v "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts.bak.$BACKUP_SUFFIX"
else
  : > "$HOME/.ssh/known_hosts"
  chmod 600 "$HOME/.ssh/known_hosts"
fi

# helper: normalize host token for known_hosts when port present
normalize_host_token() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	printf "[%s]:%s" "$host" "$port"
  else
	printf "%s" "$host"
  fi
}

# helper: fetch raw key lines for host:port
fetch_raw_keys() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	ssh-keyscan -p "$port" -T $HOSTSCAN_TIMEOUT "$host" 2>/dev/null || true
  else
	ssh-keyscan -T $HOSTSCAN_TIMEOUT "$host" 2>/dev/null || true
  fi
}

# helper: append normalized keyline to a known_hosts file if key blob not present
append_keyline_if_missing() {
  local keyline="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  touch "$target"
  chmod 600 "$target"
  local keyblob
  keyblob="$(printf "%s\n" "$keyline" | awk '{print $3}')"
  if ! grep -Fq "$keyblob" "$target" 2>/dev/null; then
	printf "%s\n" "$keyline" >> "$target"
	chmod 600 "$target"
	echo "Appended to $target"
  else
	echo "Already present in $target"
  fi
}

# iterate hosts file
while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%%#*}"
  line="$(echo "$line" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -z "$line" ] && continue

  alias_name="$(printf "%s\n" "$line" | awk '{print $1}')"
  public_name="$(printf "%s\n" "$line" | awk '{print $2}')"
  internal_ip="$(printf "%s\n" "$line" | awk '{print $3}')"
  port="$(printf "%s\n" "$line" | awk '{print $4}')"
  [ -z "$port" ] && port="22"

  echo
  echo "==== ${alias_name:-<no-alias>} public=${public_name:--} internal=${internal_ip:--} port=${port} ===="

  # build tokens to scan
  tokens=()
  [ -n "$public_name" ] && [ "$public_name" != "-" ] && tokens+=("$public_name")
  [ -n "$internal_ip" ] && [ "$internal_ip" != "-" ] && tokens+=("$internal_ip")
  [ -n "$alias_name" ] && [ "$alias_name" != "-" ] && tokens+=("$alias_name")

  # dedupe tokens
  declare -A seen
  uniq_tokens=()
  for t in "${tokens[@]}"; do
	if [ -z "${seen[$t]:-}" ]; then
	  uniq_tokens+=("$t")
	  seen[$t]=1
	fi
  done

  ALL_KEYLINES=()
  declare -A TOKEN_FPS

  for token in "${uniq_tokens[@]}"; do
	echo
	echo "Scanning $token:$port ..."
	raw="$(fetch_raw_keys "$token" "$port")"
	if [ -z "$raw" ]; then
	  echo "Could not fetch keys for $token:$port"
	  continue
	fi

	# show fingerprints
	printf "%s\n" "$raw" | ssh-keygen -lf - 2>/dev/null || true

	hosttok_norm="$(normalize_host_token "$token" "$port")"
	TOKEN_FPS["$hosttok_norm"]="$(printf "%s\n" "$raw" | ssh-keygen -lf - 2>/dev/null || true)"

	# normalize raw key lines to canonical host token
	while IFS= read -r kline; do
	  [ -z "$kline" ] && continue
	  normalized="$(printf "%s\n" "$kline" | sed -E "s/^[^ ]+/${hosttok_norm}/")"
	  ALL_KEYLINES+=("$normalized")
	done <<< "$(printf "%s\n" "$raw" | sed '/^#/d' | sed '/^$/d' | sed '/^ssh-keygen/d')"
  done

  if [ "${#ALL_KEYLINES[@]}" -eq 0 ]; then
	echo "No keys collected for ${alias_name:-<no-alias>}, skipping."
	continue
  fi

  # show summary and prompt
  echo
  echo "Summary fingerprints for ${alias_name:-<no-alias>}:"
  for k in "${!TOKEN_FPS[@]}"; do
	echo "Host token: $k"
	printf "%s\n" "${TOKEN_FPS[$k]}"
  done

  echo
  echo "Options:"
  echo "  [a] Add these keys to known_hosts"
  echo "  [r] Replace existing known_hosts entries for these host tokens with these keys"
  echo "  [s] Skip"
  read -r -p "Choose action [a/r/s] (default a): " choice
  choice="${choice:-a}"

  case "$choice" in
	r|R)
	  # remove existing entries for each host token
	  for hosttok in "${!TOKEN_FPS[@]}"; do
		ssh-keygen -R "$hosttok" 2>/dev/null || true
	  done
	  echo "Existing entries removed. Appending new keys..."
	  for k in "${ALL_KEYLINES[@]}"; do
		append_keyline_if_missing "$k" "$HOME/.ssh/known_hosts"
	  done
	  ;;
	a|A)
	  for k in "${ALL_KEYLINES[@]}"; do
		append_keyline_if_missing "$k" "$HOME/.ssh/known_hosts"
	  done
	  ;;
	*)
	  echo "Skipped ${alias_name:-<no-alias>}."
	  continue
	  ;;
  esac

  # update root known_hosts if sudo available
  if command -v sudo >/dev/null 2>&1; then
	sudo mkdir -p /root/.ssh
	sudo touch /root/.ssh/known_hosts
	sudo chmod 600 /root/.ssh/known_hosts
	for k in "${ALL_KEYLINES[@]}"; do
	  keyblob="$(printf "%s\n" "$k" | awk '{print $3}')"
	  if ! sudo grep -Fq "$keyblob" /root/.ssh/known_hosts 2>/dev/null; then
		printf "%s\n" "$k" | sudo tee -a /root/.ssh/known_hosts >/dev/null
		sudo chmod 600 /root/.ssh/known_hosts
		echo "Appended to /root/.ssh/known_hosts"
	  else
		echo "Already present in /root/.ssh/known_hosts"
	  fi
	done
  else
	echo "sudo not available; skipping root known_hosts update"
  fi

done < "$HOSTS_FILE"

echo
echo "Done. Backups kept as ~/.ssh/known_hosts.bak.*"
