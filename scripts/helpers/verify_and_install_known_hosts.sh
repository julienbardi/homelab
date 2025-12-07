#!/usr/bin/env bash
set -euo pipefail

# verify_and_install_known_hosts.sh
# Non-interactive, production-ready tool to atomically replace SSH host keys
# in ~/.ssh/known_hosts and /root/.ssh/known_hosts (via sudo).
#
# Usage:
#   ./verify_and_install_known_hosts.sh [--dry-run] known_hosts_to_check.txt
#
# Options:
#   --dry-run            Show what would change without writing files
#
# Behavior:
#   - Always performs "replace" semantics: remove existing entries for the
#     scanned host tokens and replace them with the scanned keys (atomic).
#   - Always prefers ssh-ed25519 keylines first when adding or replacing.
#   - Creates an atomic backup of ~/.ssh/known_hosts before modifying it.
#   - Updates /root/.ssh/known_hosts via sudo (requires non-interactive sudo).
#   - Uses a per-user lock to avoid concurrent runs.
#   - Logs important events via logger -t verify_known_hosts.
#   - Prints scanned keylines only when they are new or when a replace changes the file.
#   - Emits a concise summary at the end listing hosts that changed (user/root).
#
# Input file format (one entry per line):
#   alias public_name internal_ip [port]
# Use '-' for unused fields. Lines starting with '#' are ignored.

DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
	--dry-run) DRY_RUN=1; shift ;;
	--) shift; break ;;
	-*)
	  echo "Unknown option: $1" >&2
	  exit 2
	  ;;
	*) break ;;
  esac
done

HOSTS_FILE="${1:-known_hosts_to_check.txt}"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
HOSTSCAN_TIMEOUT=5

# Always prefer ed25519 and always replace (non-interactive)
PREFER_ED25519=1
AUTO_REPLACE=1

# safe lock directory (per-user fallback)
LOCKDIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/locks"
mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/verify_known_hosts.lock"

# temp files we'll create (for cleanup)
tmp_known=""
tmp_root=""

# track changes for summary
declare -a CHANGED_SUMMARY=()   # entries like "display_name:user", "display_name:root", or both "display_name:user,root"

# trap for cleanup: remove temp files and release lock
cleanup() {
  [ -n "${tmp_known:-}" ] && [ -f "$tmp_known" ] && rm -f "$tmp_known" 2>/dev/null || true
  [ -n "${tmp_root:-}" ] && [ -f "$tmp_root" ] && rm -f "$tmp_root" 2>/dev/null || true
  if command -v flock >/dev/null 2>&1; then
	flock -u 9 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# try to acquire exclusive lock on fd 9; if flock not available, warn and continue
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  if ! flock -n 9 2>/dev/null; then
	echo "Another verify_known_hosts run is active; exiting." >&2
	logger -t verify_known_hosts "Another run active; exiting"
	exit 1
  fi
else
  echo "Warning: flock not available; proceeding without exclusive lock" >&2
  logger -t verify_known_hosts "flock not available; proceeding without exclusive lock"
fi

if [ ! -f "$HOSTS_FILE" ]; then
  echo "Hosts file not found: $HOSTS_FILE" >&2
  logger -t verify_known_hosts "Hosts file not found: $HOSTS_FILE"
  exit 2
fi

# If automation will update root and sudo is present, ensure non-interactive sudo works
if command -v sudo >/dev/null 2>&1 && [ "$DRY_RUN" -eq 0 ]; then
  if ! sudo -n true 2>/dev/null; then
	echo "Error: non-interactive sudo required to update /root/.ssh/known_hosts but sudo -n failed. Aborting." >&2
	logger -t verify_known_hosts "non-interactive sudo required but sudo -n failed"
	exit 3
  fi
fi

# Ensure ~/.ssh exists and backup known_hosts atomically
mkdir -p "$HOME/.ssh"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
if [ -f "$KNOWN_HOSTS" ]; then
  tmp="$(mktemp "${HOME}/.ssh/known_hosts.bak.XXXXXX")"
  cp -p "$KNOWN_HOSTS" "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "${HOME}/.ssh/known_hosts.bak.$BACKUP_SUFFIX"
  logger -t verify_known_hosts "Backup created: ${HOME}/.ssh/known_hosts.bak.$BACKUP_SUFFIX"
  # rotate backups: keep last 5
  (cd "$HOME/.ssh" && ls -1t known_hosts.bak.* 2>/dev/null | tail -n +6 | xargs -r rm --) || true
else
  : > "$KNOWN_HOSTS"
  chmod 600 "$KNOWN_HOSTS"
fi

# helper for conditional writes (respects DRY_RUN)
safe_append() {
  local line="$1" target="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
	printf "DRY-RUN: would append to %s: %s\n" "$target" "$line"
  else
	printf "%s\n" "$line" >> "$target"
	chmod 600 "$target"
  fi
}

# Normalize host token for known_hosts when port != 22
normalize_host_token() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	printf "[%s]:%s" "$host" "$port"
  else
	printf "%s" "$host"
  fi
}

# Fetch raw key lines for host:port (returns empty on failure)
fetch_raw_keys() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	ssh-keyscan -p "$port" -T "$HOSTSCAN_TIMEOUT" "$host" 2>/dev/null || true
  else
	ssh-keyscan -T "$HOSTSCAN_TIMEOUT" "$host" 2>/dev/null || true
  fi
}

# Append keyline to target known_hosts if key blob not present
append_keyline_if_missing() {
  local keyline="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  touch "$target"
  chmod 600 "$target"
  local keyblob
  keyblob="$(printf "%s\n" "$keyline" | awk '{print $3}')"
  if ! grep -Fq "$keyblob" "$target" 2>/dev/null; then
	safe_append "$keyline" "$target"
	if [ "$DRY_RUN" -eq 0 ]; then
	  echo "➕ Appended to $target"
	  logger -t verify_known_hosts "Appended key blob to $target"
	else
	  echo "DRY-RUN: append skipped"
	fi
  else
	echo "✅ Already present in $target"
  fi
}

# Helper: check if a key blob exists in a file
keyblob_exists_in_file() {
  local keyblob="$1" file="$2"
  if [ -f "$file" ] && grep -Fq "$keyblob" "$file" 2>/dev/null; then
	return 0
  fi
  return 1
}

# Helper: remove host token lines from a file (in-place via temp)
# Arguments: hosttok file
remove_hosttok_from_file() {
  local hosttok="$1" file="$2"
  local tmpf
  tmpf="$(mktemp "${file}.tmp.XXXXXX")"
  awk -v h="$hosttok" 'BEGIN{FS=" "}{if($1!=h) print $0}' "$file" > "$tmpf"
  chmod 600 "$tmpf"
  mv -f "$tmpf" "$file"
}

# Helper: remove host tokens from a temp file (used when building atomic replacement)
remove_hosttok_from_temp() {
  local hosttok="$1" tmpfile="$2"
  local tmpf2
  tmpf2="$(mktemp "${tmpfile}.tmp.XXXXXX")"
  awk -v h="$hosttok" 'BEGIN{FS=" "}{if($1!=h) print $0}' "$tmpfile" > "$tmpf2"
  mv -f "$tmpf2" "$tmpfile"
}

# Helper: print keylines (only used when they are new/different)
print_keylines_for_host() {
  local host_display="$1"
  shift
  local -a lines=("$@")
  if [ "${#lines[@]}" -eq 0 ]; then
	return
  fi
  echo
  echo "🔐 Keys for ${host_display}:"
  for l in "${lines[@]}"; do
	echo "  $l"
  done
  echo
}

# Main loop: read hosts file
overall_fail=0
while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%%#*}"
  line="$(echo "$line" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -z "$line" ] && continue

  alias_name="$(printf "%s\n" "$line" | awk '{print $1}')"
  public_name="$(printf "%s\n" "$line" | awk '{print $2}')"
  internal_ip="$(printf "%s\n" "$line" | awk '{print $3}')"
  port="$(printf "%s\n" "$line" | awk '{print $4}')"
  [ -z "$port" ] && port="22"

  # Friendly display name: alias if set and not '-', else public, else internal, else <no-name>
  if [ -n "$alias_name" ] && [ "$alias_name" != "-" ]; then
	display_name="$alias_name"
  elif [ -n "$public_name" ] && [ "$public_name" != "-" ]; then
	display_name="$public_name"
  elif [ -n "$internal_ip" ] && [ "$internal_ip" != "-" ]; then
	display_name="$internal_ip"
  else
	display_name="<no-name>"
  fi

  echo
  echo "🔎 ${display_name}  (public=${public_name:--} internal=${internal_ip:--} port=${port})"

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
  declare -A TOKEN_KEYBLOBS  # token -> space-separated key blobs

  for token in "${uniq_tokens[@]}"; do
	echo
	echo "⤴ Scanning $token:$port ..."
	raw_keys="$(fetch_raw_keys "$token" "$port")"
	if [ -z "$raw_keys" ]; then
	  echo "⚠️  Could not fetch keys for $token:$port"
	  logger -t verify_known_hosts "Could not fetch keys for $token:$port"
	  continue
	fi

	# show fingerprints (best-effort)
	printf "%s\n" "$raw_keys" | ssh-keygen -lf - 2>/dev/null || true

	hosttok_norm="$(normalize_host_token "$token" "$port")"
	TOKEN_FPS["$hosttok_norm"]="$(printf "%s\n" "$raw_keys" | ssh-keygen -lf - 2>/dev/null || true)"

	# normalize raw key lines to canonical host token and collect key blobs
	while IFS= read -r kline; do
	  [ -z "$kline" ] && continue
	  case "$kline" in
		\#*) continue ;;
	  esac
	  normalized="$(printf "%s\n" "$kline" | sed -E "s/^[^ ]+/${hosttok_norm}/")"
	  ALL_KEYLINES+=("$normalized")
	  keyblob="$(printf "%s\n" "$kline" | awk '{print $3}')"
	  if [ -n "$keyblob" ]; then
		prev="${TOKEN_KEYBLOBS[$hosttok_norm]:-}"
		if [ -z "$prev" ]; then
		  TOKEN_KEYBLOBS[$hosttok_norm]="$keyblob"
		else
		  TOKEN_KEYBLOBS[$hosttok_norm]="$prev $keyblob"
		fi
	  fi
	done <<< "$raw_keys"
  done

  if [ "${#ALL_KEYLINES[@]}" -eq 0 ]; then
	echo "⚠️  No keys collected, skipping."
	overall_fail=1
	logger -t verify_known_hosts "No keys collected for ${display_name}; skipping"
	continue
  fi

  # Determine whether keys are already present
  all_present=true
  declare -A MISSING_KEYLINES_BY_TOKEN
  for hosttok in "${!TOKEN_KEYBLOBS[@]}"; do
	missing_blobs=()
	for blob in ${TOKEN_KEYBLOBS[$hosttok]}; do
	  if keyblob_exists_in_file "$blob" "$KNOWN_HOSTS" || keyblob_exists_in_file "$blob" "/root/.ssh/known_hosts"; then
		:
	  else
		missing_blobs+=("$blob")
	  fi
	done
	if [ "${#missing_blobs[@]}" -ne 0 ]; then
	  all_present=false
	  for kline in "${ALL_KEYLINES[@]}"; do
		blob="$(printf "%s\n" "$kline" | awk '{print $3}')"
		if [ -n "$blob" ]; then
		  for mb in "${missing_blobs[@]}"; do
			if [ "$blob" = "$mb" ] && printf "%s\n" "$kline" | grep -q "^${hosttok} "; then
			  MISSING_KEYLINES_BY_TOKEN["$hosttok"]+="$kline"$'\n'
			fi
		  done
		fi
	  done
	fi
  done

  if [ "$all_present" = true ]; then
	echo "✅ All keys present for ${display_name}"
	continue
  fi

  # Build list of missing keylines (unique)
  MISSING_KEYLINES=()
  declare -A _seen_k
  for hosttok in "${!MISSING_KEYLINES_BY_TOKEN[@]}"; do
	while IFS= read -r ml || [ -n "$ml" ]; do
	  [ -z "$ml" ] && continue
	  if [ -z "${_seen_k[$ml]:-}" ]; then
		MISSING_KEYLINES+=("$ml")
		_seen_k[$ml]=1
	  fi
	done <<< "${MISSING_KEYLINES_BY_TOKEN[$hosttok]}"
  done

  # Always prefer ed25519: reorder missing keylines to put ed25519 first
  if [ "${#MISSING_KEYLINES[@]}" -gt 0 ]; then
	ed_first=()
	others=()
	for ml in "${MISSING_KEYLINES[@]}"; do
	  if printf "%s\n" "$ml" | grep -q "ssh-ed25519"; then
		ed_first+=("$ml")
	  else
		others+=("$ml")
	  fi
	done
	MISSING_KEYLINES=("${ed_first[@]}" "${others[@]}")
  fi

  # Also reorder ALL_KEYLINES when replacing to prefer ed25519
  if [ "${#ALL_KEYLINES[@]}" -gt 0 ]; then
	ed_first_all=()
	others_all=()
	for ml in "${ALL_KEYLINES[@]}"; do
	  if printf "%s\n" "$ml" | grep -q "ssh-ed25519"; then
		ed_first_all+=("$ml")
	  else
		others_all+=("$ml")
	  fi
	done
	ALL_KEYLINES=("${ed_first_all[@]}" "${others_all[@]}")
  fi

  # Non-interactive replace (always)
  echo
  echo "🔁 Replacing entries for ${display_name} (atomic)"
  if [ "$DRY_RUN" -eq 1 ]; then
	echo "DRY-RUN: would remove existing entries for host tokens: ${!TOKEN_FPS[@]}"
	echo "DRY-RUN: would append scanned keys for ${display_name}"
	# In dry-run, show the keys that would be added (only the missing ones)
	if [ "${#MISSING_KEYLINES[@]}" -gt 0 ]; then
	  print_keylines_for_host "$display_name (would add)" "${MISSING_KEYLINES[@]}"
	fi
	logger -t verify_known_hosts "DRY-RUN replace for ${display_name}"
	# record as "would-change" in summary
	CHANGED_SUMMARY+=("${display_name}:would-change")
	continue
  else
	tmp_known="$(mktemp "${HOME}/.ssh/known_hosts.tmp.XXXXXX")"
	cp -p "$KNOWN_HOSTS" "$tmp_known"
	chmod 600 "$tmp_known"
	# remove each host token from temp
	for hosttok in "${!TOKEN_FPS[@]}"; do
	  remove_hosttok_from_temp "$hosttok" "$tmp_known"
	done
	# append all scanned keylines to temp
	for k in "${ALL_KEYLINES[@]}"; do
	  printf "%s\n" "$k" >> "$tmp_known"
	done
	chmod 600 "$tmp_known"

	# Only replace if content differs
	if cmp -s "$KNOWN_HOSTS" "$tmp_known"; then
	  echo "ℹ️  No changes required for $KNOWN_HOSTS"
	  logger -t verify_known_hosts "No changes required for $KNOWN_HOSTS (skipping replace for ${display_name})"
	  rm -f "$tmp_known"
	  tmp_known=""
	else
	  # Before moving, compute which keylines are new vs existing (for user file)
	  # Extract key blobs from existing file for the host tokens
	  new_user_keylines=()
	  for k in "${ALL_KEYLINES[@]}"; do
		blob="$(printf "%s\n" "$k" | awk '{print $3}')"
		if ! keyblob_exists_in_file "$blob" "$KNOWN_HOSTS"; then
		  new_user_keylines+=("$k")
		fi
	  done

	  mv -f "$tmp_known" "$KNOWN_HOSTS"
	  tmp_known=""
	  echo "✅ Replaced entries in $KNOWN_HOSTS for tokens: ${!TOKEN_FPS[@]}"
	  logger -t verify_known_hosts "Replaced entries in $KNOWN_HOSTS for ${display_name}"

	  # print only the new keylines that were added (or all if none matched)
	  if [ "${#new_user_keylines[@]}" -gt 0 ]; then
		print_keylines_for_host "$display_name (new user keys)" "${new_user_keylines[@]}"
	  else
		# If no new_user_keylines found, still show the scanned keys (replace changed something)
		print_keylines_for_host "$display_name (scanned keys)" "${ALL_KEYLINES[@]}"
	  fi

	  # record change
	  CHANGED_SUMMARY+=("${display_name}:user")
	fi
  fi

  # update root known_hosts if sudo available (respect DRY_RUN)
  if command -v sudo >/dev/null 2>&1; then
	if [ "$DRY_RUN" -eq 1 ]; then
	  echo "DRY-RUN: would update /root/.ssh/known_hosts (requires sudo)"
	  # In dry-run, show keys that would be added to root (same as user missing lines)
	  if [ "${#MISSING_KEYLINES[@]}" -gt 0 ]; then
		print_keylines_for_host "$display_name (would add to root)" "${MISSING_KEYLINES[@]}"
	  fi
	  # already recorded would-change above
	else
	  sudo mkdir -p /root/.ssh
	  sudo touch /root/.ssh/known_hosts
	  sudo chmod 600 /root/.ssh/known_hosts
	  tmp_root="$(mktemp "/tmp/known_hosts.root.tmp.XXXXXX")"
	  sudo cp -p /root/.ssh/known_hosts "$tmp_root"
	  sudo chmod 600 "$tmp_root"
	  # remove host tokens from tmp_root
	  for hosttok in "${!TOKEN_FPS[@]}"; do
		tmp2="$(mktemp "/tmp/known_hosts.root.tmp2.XXXXXX")"
		sudo awk -v h="$hosttok" 'BEGIN{FS=" "}{if($1!=h) print $0}' "$tmp_root" > "$tmp2"
		sudo mv -f "$tmp2" "$tmp_root"
	  done
	  # append all scanned keylines to tmp_root
	  for k in "${ALL_KEYLINES[@]}"; do
		printf "%s\n" "$k" | sudo tee -a "$tmp_root" >/dev/null
	  done
	  sudo chmod 600 "$tmp_root"

	  # Only replace root known_hosts if content differs
	  if sudo cmp -s /root/.ssh/known_hosts "$tmp_root"; then
		echo "ℹ️  No changes required for /root/.ssh/known_hosts"
		logger -t verify_known_hosts "No changes required for /root/.ssh/known_hosts (skipping replace for ${display_name})"
		sudo rm -f "$tmp_root"
		tmp_root=""
	  else
		# compute new keylines for root by checking blobs against existing root file
		new_root_keylines=()
		for k in "${ALL_KEYLINES[@]}"; do
		  blob="$(printf "%s\n" "$k" | awk '{print $3}')"
		  if ! sudo grep -Fq "$blob" /root/.ssh/known_hosts 2>/dev/null; then
			new_root_keylines+=("$k")
		  fi
		done

		sudo mv -f "$tmp_root" /root/.ssh/known_hosts
		tmp_root=""
		echo "✅ Replaced entries in /root/.ssh/known_hosts for tokens: ${!TOKEN_FPS[@]}"
		logger -t verify_known_hosts "Replaced entries in /root/.ssh/known_hosts for ${display_name}"

		# print only the new keylines that were added to root (or all scanned if none matched)
		if [ "${#new_root_keylines[@]}" -gt 0 ]; then
		  print_keylines_for_host "$display_name (new root keys)" "${new_root_keylines[@]}"
		else
		  print_keylines_for_host "$display_name (scanned keys for root)" "${ALL_KEYLINES[@]}"
		fi

		# update CHANGED_SUMMARY: if host already recorded as user, append root; else add root
		found_index=-1
		for i in "${!CHANGED_SUMMARY[@]}"; do
		  if printf "%s\n" "${CHANGED_SUMMARY[$i]}" | grep -q "^${display_name}:"; then
			found_index="$i"
			break
		  fi
		done
		if [ "$found_index" -ge 0 ]; then
		  # append ",root" if not already present
		  if ! printf "%s\n" "${CHANGED_SUMMARY[$found_index]}" | grep -q "root"; then
			CHANGED_SUMMARY[$found_index]="${CHANGED_SUMMARY[$found_index]},root"
		  fi
		else
		  CHANGED_SUMMARY+=("${display_name}:root")
		fi
	  fi
	fi
  else
	echo "⚠️  sudo not available; skipped root update"
	logger -t verify_known_hosts "sudo not available; skipped root update for ${display_name}"
  fi

done < "$HOSTS_FILE"

# Final concise summary
echo
if [ "${#CHANGED_SUMMARY[@]}" -eq 0 ]; then
  echo "✅ No changes detected for any hosts."
  logger -t verify_known_hosts "No changes detected in run"
else
  echo "🔔 Changes detected for the following hosts:"
  for entry in "${CHANGED_SUMMARY[@]}"; do
	# entry format: display_name:tag[,tag]
	echo "  - $entry"
  done
  logger -t verify_known_hosts "Changes detected: ${CHANGED_SUMMARY[*]}"
fi

echo
echo "Done. Backups: ~/.ssh/known_hosts.bak.*"
logger -t verify_known_hosts "Completed run; exit code ${overall_fail}"
exit "$overall_fail"
