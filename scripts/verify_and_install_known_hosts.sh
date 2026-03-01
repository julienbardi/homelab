#!/usr/bin/env bash
set -euo pipefail

# verify_and_install_known_hosts.sh
# Production-ready: atomically ensure SSH host keys for tokens listed in a hosts file.
# Usage:
#   ./verify_and_install_known_hosts.sh [--dry-run] known_hosts_to_check.txt
#
# Behavior:
# - Scans each host token (public, internal, alias) with ssh-keyscan.
# - For each host processed, removes only that host's tokens from known_hosts,
#   appends the freshly scanned keys (preferring ed25519), and atomically replaces
#   the file only when the canonicalized content differs.
# - Performs the same for /root/.ssh/known_hosts using sudo; all root-side reads/writes
#   are executed as root to avoid permission races.
# - Prints only new keylines when keys are added; emits a concise summary at the end.
# - Respects --dry-run (no writes) and uses a per-user flock to avoid concurrent runs.
# - Parallelizes the ssh-keyscan phase per host while keeping all file mutations sequential.

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
	--dry-run) DRY_RUN=1; shift ;;
	--) shift; break ;;
	-*) echo "Unknown option: $1" >&2; exit 2 ;;
	*) break ;;
  esac
done

HOSTS_FILE="${1:-known_hosts_to_check.txt}"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
HOSTSCAN_TIMEOUT=5
LC_ALL=C

LOCKDIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/locks"
mkdir -p "$LOCKDIR"
LOCKFILE="$LOCKDIR/verify_known_hosts.lock"

# temp vars for cleanup
tmp_known=""
tmp_known_canon=""
tmp_root=""
tmp_root_canon=""
tmp_local_root_copy=""
tmp_local_root_canon=""
user_all_tmp=""
TMPDIR_SCAN=""

declare -a CHANGED_SUMMARY=()

# shellcheck disable=SC2317
cleanup() {
  if [ -n "${tmp_known:-}" ] && [ -f "$tmp_known" ]; then
	rm -f "$tmp_known" 2>/dev/null || true
  fi

  if [ -n "${tmp_known_canon:-}" ] && [ -f "$tmp_known_canon" ]; then
	rm -f "$tmp_known_canon" 2>/dev/null || true
  fi

  if [ -n "${tmp_root:-}" ]; then
	sudo rm -f "$tmp_root" 2>/dev/null || true
  fi

  if [ -n "${tmp_root_canon:-}" ] && [ -f "$tmp_root_canon" ]; then
	rm -f "$tmp_root_canon" 2>/dev/null || true
  fi

  if [ -n "${tmp_local_root_copy:-}" ] && [ -f "$tmp_local_root_copy" ]; then
	rm -f "$tmp_local_root_copy" 2>/dev/null || true
  fi

  if [ -n "${tmp_local_root_canon:-}" ] && [ -f "$tmp_local_root_canon" ]; then
	rm -f "$tmp_local_root_canon" 2>/dev/null || true
  fi

  if [ -n "${user_all_tmp:-}" ] && [ -f "$user_all_tmp" ]; then
	rm -f "$user_all_tmp" 2>/dev/null || true
  fi

  if [ -n "${TMPDIR_SCAN:-}" ] && [ -d "$TMPDIR_SCAN" ]; then
	rm -rf "$TMPDIR_SCAN" 2>/dev/null || true
  fi

  if command -v flock >/dev/null 2>&1; then
	flock -u 9 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Acquire lock
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE"
  if ! flock -n 9 2>/dev/null; then
	echo "Another verify_known_hosts run is active; exiting." >&2
	logger -t verify_known_hosts "Another run active; exiting"
	exit 1
  fi
else
  logger -t verify_known_hosts "flock not available; proceeding without exclusive lock"
fi

if [ ! -f "$HOSTS_FILE" ]; then
  echo "Hosts file not found: $HOSTS_FILE" >&2
  logger -t verify_known_hosts "Hosts file not found: $HOSTS_FILE"
  exit 2
fi

# If we will update root, require non-interactive sudo (unless dry-run)
if command -v sudo >/dev/null 2>&1 && [ "$DRY_RUN" -eq 0 ]; then
  if ! sudo -n true 2>/dev/null; then
	echo "Error: non-interactive sudo required to update /root/.ssh/known_hosts but sudo -n failed. Aborting." >&2
	logger -t verify_known_hosts "non-interactive sudo required but sudo -n failed"
	exit 3
  fi
fi

# Ensure user known_hosts exists (do NOT create a backup unless we will change the file)
mkdir -p "$HOME/.ssh"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
if [ ! -f "$KNOWN_HOSTS" ]; then
  : > "$KNOWN_HOSTS"
  chmod 600 "$KNOWN_HOSTS"
fi

# canonicalize a file: trim whitespace, remove empty lines, sort unique
canonicalize_file() {
  local infile="$1" outfile="$2"
  awk '{
	gsub(/\r$/,"");
	sub(/^[ \t]+/,"");
	sub(/[ \t]+$/,"");
	if (length($0)>0) print $0
  }' "$infile" | sort -u > "$outfile"
  chmod 600 "$outfile" || true
}

# shellcheck disable=SC2317
safe_append() {
  local line="$1" target="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
	printf "DRY-RUN: would append to %s: %s\n" "$target" "$line"
  else
	printf "%s\n" "$line" >> "$target"
	chmod 600 "$target"
  fi
}

normalize_host_token() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	printf "[%s]:%s" "$host" "$port"
  else
	printf "%s" "$host"
  fi
}

fetch_raw_keys() {
  local host="$1" port="$2"
  if [ -n "$port" ] && [ "$port" != "22" ]; then
	ssh-keyscan -p "$port" -T "$HOSTSCAN_TIMEOUT" "$host" 2>/dev/null || true
  else
	ssh-keyscan -T "$HOSTSCAN_TIMEOUT" "$host" 2>/dev/null || true
  fi
}

# Check if a key blob exists for a specific host token in a file.
# Arguments: blob hosttok file
keyblob_exists_for_token_in_file() {
  local blob="$1" hosttok="$2" file="$3"
  [ -f "$file" ] || return 1
  awk -v h="$hosttok" -v b="$blob" 'BEGIN{FS=" "}{
	n = split($1, a, ",");
	for(i=1;i<=n;i++){
	  if(a[i]==h && index($0,b)) { exit 0 }
	}
  }
  END { exit 1 }' "$file" 2>/dev/null
}

# Remove host token lines from a temp file (handles comma-separated host lists)
# Arguments: hosttok tmpfile
remove_hosttok_from_temp() {
  local hosttok="$1" tmpfile="$2"
  local tmpf2
  tmpf2="$(mktemp "${tmpfile}.tmp.XXXXXX")"
  awk -v h="$hosttok" 'BEGIN{FS=" "}{
	n = split($1, a, ",");
	keep = 1;
	for(i=1;i<=n;i++){
	  if(a[i]==h){ keep=0; break }
	}
	if(keep) print $0
  }' "$tmpfile" > "$tmpf2"
  mv -f "$tmpf2" "$tmpfile"
}

print_keylines_for_host() {
  local host_display="$1"; shift
  local -a lines=("$@")
  [ "${#lines[@]}" -eq 0 ] && return
  echo
  echo "🔐 Keys for ${host_display}:"
  for l in "${lines[@]}"; do
	echo "  $l"
  done
  echo
}

# Phase 1: scan one host (parallelizable, no printing)
scan_one_host() {
  local alias_name="$1" public_name="$2" internal_ip="$3" port="$4" display_name="$5" outfile="$6"

  # Build tokens
  local tokens=()
  [ -n "$public_name" ]  && [ "$public_name"  != "-" ] && tokens+=("$public_name")
  [ -n "$internal_ip" ]  && [ "$internal_ip"  != "-" ] && tokens+=("$internal_ip")
  [ -n "$alias_name" ]   && [ "$alias_name"   != "-" ] && tokens+=("$alias_name")

  # Deduplicate
  declare -A seen=()
  local uniq_tokens=()
  for t in "${tokens[@]}"; do
	if [ -z "${seen[$t]:-}" ]; then
	  uniq_tokens+=("$t")
	  seen[$t]=1
	fi
  done

  local ALL_KEYLINES=()
  declare -A TOKEN_FPS=()
  declare -A TOKEN_KEYBLOBS=()

  for token in "${uniq_tokens[@]}"; do
	raw_keys="$(fetch_raw_keys "$token" "$port")"
	if [ -z "$raw_keys" ]; then
	  continue
	fi

	hosttok_norm="$(normalize_host_token "$token" "$port")"
	TOKEN_FPS["$hosttok_norm"]="$(printf "%s\n" "$raw_keys" | ssh-keygen -lf - 2>/dev/null || true)"

	while IFS= read -r kline; do
	  [ -z "$kline" ] && continue
	  case "$kline" in \#*) continue ;; esac
	  normalized="$(printf "%s\n" "$kline" | sed -E "s/^[^ ]+/${hosttok_norm}/")"
	  ALL_KEYLINES+=("$normalized")
	  blob="$(printf "%s\n" "$kline" | awk '{print $3}')"
	  if [ -n "$blob" ]; then
		prev="${TOKEN_KEYBLOBS[$hosttok_norm]:-}"
		if [ -z "$prev" ]; then
		  TOKEN_KEYBLOBS[$hosttok_norm]="$blob"
		else
		  TOKEN_KEYBLOBS[$hosttok_norm]="$prev $blob"
		fi
	  fi
	done <<< "$raw_keys"
  done

  {
	printf 'display_name=%q\n' "$display_name"
	printf 'port=%q\n' "$port"

	printf 'TOKENS=('
	for t in "${uniq_tokens[@]}"; do printf '%q ' "$t"; done
	printf ')\n'

	printf 'ALL_KEYLINES=('
	for l in "${ALL_KEYLINES[@]}"; do printf '%q ' "$l"; done
	printf ')\n'

	printf 'declare -A TOKEN_FPS=(\n'
	for k in "${!TOKEN_FPS[@]}"; do printf '[%q]=%q\n' "$k" "${TOKEN_FPS[$k]}"; done
	printf ')\n'

	printf 'declare -A TOKEN_KEYBLOBS=(\n'
	for k in "${!TOKEN_KEYBLOBS[@]}"; do printf '[%q]=%q\n' "$k" "${TOKEN_KEYBLOBS[$k]}"; done
	printf ')\n'
  } > "$outfile"
}

overall_fail=0

# Phase 1: parallel scanning of all hosts
TMPDIR_SCAN="$(mktemp -d "${HOME}/.verify_known_hosts.scan.XXXXXX")"
declare -a HOST_META=()

while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%%#*}"
  line="$(echo "$line" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -z "$line" ] && continue

  alias_name="$(printf "%s\n" "$line" | awk '{print $1}')"
  public_name="$(printf "%s\n" "$line" | awk '{print $2}')"
  internal_ip="$(printf "%s\n" "$line" | awk '{print $3}')"
  port="$(printf "%s\n" "$line" | awk '{print $4}')"
  [ -z "$port" ] && port="22"

  if [ -n "$alias_name" ] && [ "$alias_name" != "-" ]; then
	display_name="$alias_name"
  elif [ -n "$public_name" ] && [ "$public_name" != "-" ]; then
	display_name="$public_name"
  elif [ -n "$internal_ip" ] && [ "$internal_ip" != "-" ]; then
	display_name="$internal_ip"
  else
	display_name="<no-name>"
  fi

  outfile="$(mktemp "${TMPDIR_SCAN}/scan.${display_name}.XXXXXX")"
  HOST_META+=("$display_name|$alias_name|$public_name|$internal_ip|$port|$outfile")

  scan_one_host "$alias_name" "$public_name" "$internal_ip" "$port" "$display_name" "$outfile" &
done < "$HOSTS_FILE"

wait

# Phase 2: sequential updates and operator-visible output
for entry in "${HOST_META[@]}"; do
  IFS='|' read -r display_name alias_name public_name internal_ip port outfile <<< "$entry"

  echo
  echo "🔎 ${display_name}  (public=${public_name:--} internal=${internal_ip:--} port=${port})"

  # Load scan result
  # shellcheck disable=SC1090
  source "$outfile" || true

  # If TOKENS not set (no scan result), initialize empty
  : "${TOKENS:=()}"
  : "${ALL_KEYLINES:=()}"

  # Print per-token scan + fingerprints based on TOKEN_FPS
  for token in "${TOKENS[@]}"; do
	echo
	echo "⤴ Scanning $token:$port ..."
	hosttok_norm="$(normalize_host_token "$token" "$port")"
	if [ -n "${TOKEN_FPS[$hosttok_norm]:-}" ]; then
	  printf "%s\n" "${TOKEN_FPS[$hosttok_norm]}" || true
	else
	  echo "� ️  Could not fetch keys for $token:$port"
	  logger -t verify_known_hosts "Could not fetch keys for $token:$port"
	fi
  done

  if [ "${#ALL_KEYLINES[@]}" -eq 0 ]; then
	echo "� ️  No keys collected, skipping."
	overall_fail=1
	logger -t verify_known_hosts "No keys collected for ${display_name}; skipping"
	continue
  fi

  # Determine whether keys are already present for each token (token-specific)
  all_present=true
  declare -A MISSING_KEYLINES_BY_TOKEN=()
  for hosttok in "${!TOKEN_KEYBLOBS[@]}"; do
	missing_blobs=()
	for blob in ${TOKEN_KEYBLOBS[$hosttok]}; do
	  if keyblob_exists_for_token_in_file "$blob" "$hosttok" "$KNOWN_HOSTS" || keyblob_exists_for_token_in_file "$blob" "$hosttok" "/root/.ssh/known_hosts"; then
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

  # Build unique missing keylines list (for display / root append)
  MISSING_KEYLINES=()
  declare -A _seen_k=()
  for hosttok in "${!MISSING_KEYLINES_BY_TOKEN[@]}"; do
	while IFS= read -r ml || [ -n "$ml" ]; do
	  [ -z "$ml" ] && continue
	  if [ -z "${_seen_k[$ml]:-}" ]; then
		MISSING_KEYLINES+=("$ml")
		_seen_k[$ml]=1
	  fi
	done <<< "${MISSING_KEYLINES_BY_TOKEN[$hosttok]}"
  done

  # Prefer ed25519 first in missing list and in all lines
  if [ "${#MISSING_KEYLINES[@]}" -gt 0 ]; then
	ed_first=(); others=()
	for ml in "${MISSING_KEYLINES[@]}"; do
	  if printf "%s\n" "$ml" | grep -q "ssh-ed25519"; then ed_first+=("$ml"); else others+=("$ml"); fi
	done
	MISSING_KEYLINES=("${ed_first[@]}" "${others[@]}")
  fi
  if [ "${#ALL_KEYLINES[@]}" -gt 0 ]; then
	ed_first_all=(); others_all=()
	for ml in "${ALL_KEYLINES[@]}"; do
	  if printf "%s\n" "$ml" | grep -q "ssh-ed25519"; then ed_first_all+=("$ml"); else others_all+=("$ml"); fi
	done
	ALL_KEYLINES=("${ed_first_all[@]}" "${others_all[@]}")
  fi

  echo
  echo "🔁 Replacing entries for ${display_name} (atomic)"

  # Build TOKEN_FPS keys list for this host
  tokens_for_host=()
  for t in "${!TOKEN_FPS[@]}"; do
	tokens_for_host+=("$t")
  done

  if [ "$DRY_RUN" -eq 1 ]; then
	echo "DRY-RUN: would remove existing entries for host tokens: $(printf '%s ' "${tokens_for_host[@]}")"
	echo "DRY-RUN: would append scanned keys for ${display_name}"
	[ "${#MISSING_KEYLINES[@]}" -gt 0 ] && print_keylines_for_host "$display_name (would add)" "${MISSING_KEYLINES[@]}"
	logger -t verify_known_hosts "DRY-RUN replace for ${display_name}"
	CHANGED_SUMMARY+=("${display_name}:would-change")
	continue
  fi

  # Build candidate user known_hosts: remove only tokens for this host, then append this host's scanned keys
  tmp_known="$(mktemp "${HOME}/.ssh/known_hosts.tmp.XXXXXX")"
  cp -p "$KNOWN_HOSTS" "$tmp_known"
  chmod 600 "$tmp_known"
  for hosttok in "${tokens_for_host[@]}"; do
	remove_hosttok_from_temp "$hosttok" "$tmp_known"
  done
  for k in "${ALL_KEYLINES[@]}"; do
	printf "%s\n" "$k" >> "$tmp_known"
  done
  chmod 600 "$tmp_known"

  # Canonicalize and compare to avoid ordering/whitespace false positives
  tmp_known_canon="$(mktemp "${HOME}/.ssh/known_hosts.canon.tmp.XXXXXX")"
  canonicalize_file "$tmp_known" "$tmp_known_canon"
  known_canon="$(mktemp "${HOME}/.ssh/known_hosts.canon.cur.XXXXXX")"
  canonicalize_file "$KNOWN_HOSTS" "$known_canon"

  if cmp -s "$known_canon" "$tmp_known_canon"; then
	echo "ℹ️  No changes required for $KNOWN_HOSTS"
	logger -t verify_known_hosts "No changes required for $KNOWN_HOSTS (skipping replace for ${display_name})"
	rm -f "$tmp_known" "$tmp_known_canon" "$known_canon"
	tmp_known=""; tmp_known_canon=""
  else
	# Before overwriting, create a backup of the existing known_hosts (only when we will change it)
	bak="$(mktemp "${HOME}/.ssh/known_hosts.bak.XXXXXX")"
	cp -p "$KNOWN_HOSTS" "$bak"
	chmod 600 "$bak"
	mv -f "$bak" "${HOME}/.ssh/known_hosts.bak.$BACKUP_SUFFIX"
	logger -t verify_known_hosts "Backup created: ${HOME}/.ssh/known_hosts.bak.$BACKUP_SUFFIX"
	# rotate backups: keep last 5
	( cd "$HOME/.ssh" && \
		find . -maxdepth 1 -type f -name 'known_hosts.bak.*' -printf '%T@ %p\n' 2>/dev/null \
		| sort -nr \
		| awk 'NR>5 { sub(/^[^ ]+ /, ""); print }' \
		| xargs -r --no-run-if-empty rm -- ) || true

	# Determine which keylines are new for user file
	new_user_keylines=()
	for k in "${ALL_KEYLINES[@]}"; do
	  blob="$(printf "%s\n" "$k" | awk '{print $3}')"
	  if ! grep -Fq "$blob" "$known_canon" 2>/dev/null; then
		new_user_keylines+=("$k")
	  fi
	done

	mv -f "$tmp_known" "$KNOWN_HOSTS"
	rm -f "$tmp_known_canon" "$known_canon"
	tmp_known=""; tmp_known_canon=""
	echo "✅ Replaced entries in $KNOWN_HOSTS for tokens: $(printf '%s ' "${tokens_for_host[@]}")"
	logger -t verify_known_hosts "Replaced entries in $KNOWN_HOSTS for ${display_name}"

	if [ "${#new_user_keylines[@]}" -gt 0 ]; then
	  print_keylines_for_host "$display_name (new user keys)" "${new_user_keylines[@]}"
	else
	  print_keylines_for_host "$display_name (scanned keys)" "${ALL_KEYLINES[@]}"
	fi

	CHANGED_SUMMARY+=("${display_name}:user")
  fi

  # Root update: perform entire root-side work inside a single sudo shell block.
  if command -v sudo >/dev/null 2>&1; then
	if [ "$DRY_RUN" -eq 1 ]; then
	  echo "DRY-RUN: would update /root/.ssh/known_hosts (requires sudo)"
	  [ "${#MISSING_KEYLINES[@]}" -gt 0 ] && print_keylines_for_host "$display_name (would add to root)" "${MISSING_KEYLINES[@]}"
	else
	  sudo mkdir -p /root/.ssh
	  sudo touch /root/.ssh/known_hosts
	  sudo chmod 600 /root/.ssh/known_hosts

	  # Write ALL_KEYLINES to a user-owned temp file so we can hand it to the root block.
	  user_all_tmp="$(mktemp "${HOME}/known_hosts.all.XXXXXX")"
	  for k in "${ALL_KEYLINES[@]}"; do
		printf "%s\n" "$k" >> "$user_all_tmp"
	  done
	  chmod 600 "$user_all_tmp"

	  # Build an array of host tokens to pass as args to the sudo block
	  tokens_args=()
	  for t in "${tokens_for_host[@]}"; do
		tokens_args+=("$t")
	  done

	  # Create a user-owned canonical of current root known_hosts for later comparison
	  tmp_local_root_copy="$(mktemp "${HOME}/known_hosts.root.copy.XXXXXX")"
	  sudo cat /root/.ssh/known_hosts | tee "$tmp_local_root_copy" >/dev/null
	  chmod 600 "$tmp_local_root_copy"
	  tmp_local_root_canon="$(mktemp "${HOME}/known_hosts.root.canon.cur.XXXXXX")"
	  canonicalize_file "$tmp_local_root_copy" "$tmp_local_root_canon"

	  # Run a single sudo shell that:
	  #  - creates a root-owned tmp copy of /root/.ssh/known_hosts
	  #  - removes only the tokens passed as args
	  #  - appends the scanned keys from the user-owned temp file (read inside root)
	  #  - moves the tmp into place
	  sudo sh -s "$user_all_tmp" "${tokens_args[@]}" <<'ROOTSCRIPT'
set -euo pipefail
user_all_tmp="$1"
shift
tokens=("$@")

tmp_root="$(mktemp -p /tmp known_hosts.root.tmp.XXXXXX)"
cp -p /root/.ssh/known_hosts "$tmp_root"
chmod 600 "$tmp_root"

for hosttok in "${tokens[@]}"; do
  tmp2="$(mktemp -p /tmp known_hosts.root.tmp2.XXXXXX)"
  awk -v h="$hosttok" 'BEGIN{FS=" "}{
	n = split($1, a, ",");
	keep = 1;
	for(i=1;i<=n;i++){ if(a[i]==h){ keep=0; break } }
	if(keep) print $0
  }' "$tmp_root" > "$tmp2"
  mv -f "$tmp2" "$tmp_root"
  chmod 600 "$tmp_root"
done

# Append scanned keys (read from the user-owned temp file) into root tmp
cat "$user_all_tmp" >> "$tmp_root"
chmod 600 "$tmp_root"

# Move into place atomically
mv -f "$tmp_root" /root/.ssh/known_hosts
chmod 600 /root/.ssh/known_hosts
ROOTSCRIPT

	  # Remove the user-owned temp now that root has consumed it
	  rm -f "$user_all_tmp"
	  user_all_tmp=""

	  # Create a user-owned copy of the newly-installed root known_hosts for canonical comparison
	  tmp_local_root_copy_new="$(mktemp "${HOME}/known_hosts.root.copy.new.XXXXXX")"
	  sudo cat /root/.ssh/known_hosts | tee "$tmp_local_root_copy_new" >/dev/null
	  chmod 600 "$tmp_local_root_copy_new"
	  tmp_local_root_canon_new="$(mktemp "${HOME}/known_hosts.root.canon.new.XXXXXX")"
	  canonicalize_file "$tmp_local_root_copy_new" "$tmp_local_root_canon_new"

	  # Compare previous canonical (tmp_local_root_canon) with the new canonical
	  if ! cmp -s "$tmp_local_root_canon" "$tmp_local_root_canon_new"; then
		# Determine new root keylines by comparing blobs against previous canonical
		new_root_keylines=()
		for k in "${ALL_KEYLINES[@]}"; do
		  blob="$(printf "%s\n" "$k" | awk '{print $3}')"
		  if ! grep -Fq "$blob" "$tmp_local_root_canon" 2>/dev/null; then
			new_root_keylines+=("$k")
		  fi
		done

		echo "✅ Replaced entries in /root/.ssh/known_hosts for tokens: $(printf '%s ' "${tokens_for_host[@]}")"
		logger -t verify_known_hosts "Replaced entries in /root/.ssh/known_hosts for ${display_name}"

		if [ "${#new_root_keylines[@]}" -gt 0 ]; then
		  print_keylines_for_host "$display_name (new root keys)" "${new_root_keylines[@]}"
		else
		  print_keylines_for_host "$display_name (scanned keys for root)" "${ALL_KEYLINES[@]}"
		fi

		# Only now update the summary
		found_index=-1
		for i in "${!CHANGED_SUMMARY[@]}"; do
		  if printf "%s\n" "${CHANGED_SUMMARY[$i]}" | grep -q "^${display_name}:"; then
			found_index="$i"
			break
		  fi
		done
		if [ "$found_index" -ge 0 ]; then
		  if ! printf "%s\n" "${CHANGED_SUMMARY[$found_index]}" | grep -q "root"; then
			CHANGED_SUMMARY[$found_index]="${CHANGED_SUMMARY[$found_index]},root"
		  fi
		else
		  CHANGED_SUMMARY+=("${display_name}:root")
		fi
	  else
		echo "ℹ️  Installed root file but canonical content unchanged for ${display_name}"
		logger -t verify_known_hosts "Installed root file but canonical content unchanged for ${display_name}"
	  fi

	  # cleanup temporary canonical copies
	  rm -f "$tmp_local_root_copy" "$tmp_local_root_canon" "$tmp_local_root_copy_new" "$tmp_local_root_canon_new" 2>/dev/null || true
	  tmp_root=""; tmp_root_canon=""; tmp_local_root_copy=""
	fi
  else
	echo "� ️  sudo not available; skipped root update"
	logger -t verify_known_hosts "sudo not available; skipped root update for ${display_name}"
  fi

done

# Final concise summary
echo
if [ "${#CHANGED_SUMMARY[@]}" -eq 0 ]; then
  echo "✅ No changes detected for any hosts."
  logger -t verify_known_hosts "No changes detected in run"
else
  echo "🔔 Changes detected for the following hosts:"
  for entry in "${CHANGED_SUMMARY[@]}"; do
	echo "  - $entry"
  done
  logger -t verify_known_hosts "Changes detected: ${CHANGED_SUMMARY[*]}"
fi

echo
echo "Done. Backups: ~/.ssh/known_hosts.bak.*"
logger -t verify_known_hosts "Completed run; exit code ${overall_fail}"
exit "$overall_fail"
