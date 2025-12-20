#!/usr/bin/env bash
# rotate-unbound-rootkeys.sh
# Keeps newest N files, newest per UTC day for D days, newest per UTC month for M months.
# Deletes by default. Edit KEEP_NEWEST/DAYS/MONTHS at top to change behavior.
# to deploy, use
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/rotate-unbound-rootkeys.sh /usr/local/bin/rotate-unbound-rootkeys.sh;sudo chmod 755 /usr/local/bin/rotate-unbound-rootkeys.sh
#   sudo rotate-unbound-rootkeys.sh; ls -la /var/lib/unbound/root.key.* | wc -l
set -euo pipefail

# --- edit these ---
KEEP_NEWEST=5
DAYS=5
MONTHS=60
# -------------------

TARGET_DIR=/var/lib/unbound
PATTERN='root.key.*'
LIVE='root.key'

printf '⚙️  CONFIG: TARGET_DIR=%s KEEP_NEWEST=%s DAYS=%s MONTHS=%s\n' \
  "$TARGET_DIR" "$KEEP_NEWEST" "$DAYS" "$MONTHS"

cd -- "$TARGET_DIR" || { printf '❌ FATAL: cannot chdir to %s\n' "$TARGET_DIR" >&2; exit 1; }

shopt -s nullglob
# expand safely into array of pathnames
mapfile -t cands < <(printf '%s\n' $PATTERN)
shopt -u nullglob

# exclude live file
tmp=()
for f in "${cands[@]}"; do
  if [[ "$(basename -- "$f")" == "$LIVE" ]]; then
    printf '🔍 DEBUG: skipping live file %s\n' "$f"
    continue
  fi
  tmp+=("$f")
done
cands=("${tmp[@]}")

if [[ ${#cands[@]} -eq 0 ]]; then
  printf 'ℹ️  INFO: no candidate backup files found - nothing to rotate\n'
  exit 0
fi

# build "epoch<TAB>file" entries
entries=()
for f in "${cands[@]}"; do
  if ! epoch=$(stat -c %Y -- "$f" 2>/dev/null); then
    printf '⚠️  WARN: stat failed on %s - skipping\n' "$f"
    continue
  fi
  entries+=("$epoch"$'\t'"$f")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  printf 'ℹ️  INFO: no stat-able candidate backups found; nothing to rotate\n'
  exit 0
fi

# sort ascending by epoch
IFS=$'\n' sorted=($(printf '%s\n' "${entries[@]}" | sort -n -t$'\t' -k1,1)); unset IFS

# expand into 0-based arrays
files=()
epochs=()
for item in "${sorted[@]}"; do
  epochs+=("${item%%$'\t'*}")
  files+=("${item#*$'\t'}")
done
n=${#files[@]}

declare -A keep
# keep newest N
for ((i=n-1; i>=0 && i>n-1-KEEP_NEWEST; i--)); do
  keep["${files[i]}"]=1
done

# keep newest per UTC day
for ((d=0; d<DAYS; d++)); do
  target=$(date -u -d "-$d day" +%Y-%m-%d)
  best_idx=-1
  best_e=0
  for ((i=0; i<n; i++)); do
    e=${epochs[i]:-0}
    if ! [[ $e =~ ^[0-9]+$ ]]; then continue; fi
    file_day=$(date -u -d "@$e" +%Y-%m-%d)
    if [[ "$file_day" == "$target" && "$e" -gt "$best_e" ]]; then
      best_e=$e; best_idx=$i
    fi
  done
  if (( best_idx >= 0 )); then
    keep["${files[best_idx]}"]=1
  fi
done

# keep newest per UTC month
for ((m=0; m<MONTHS; m++)); do
  target=$(date -u -d "-$m month" +%Y-%m)
  best_idx=-1
  best_e=0
  for ((i=0; i<n; i++)); do
    e=${epochs[i]:-0}
    if ! [[ $e =~ ^[0-9]+$ ]]; then continue; fi
    file_mon=$(date -u -d "@$e" +%Y-%m)
    if [[ "$file_mon" == "$target" && "$e" -gt "$best_e" ]]; then
      best_e=$e; best_idx=$i
    fi
  done
  if (( best_idx >= 0 )); then
    keep["${files[best_idx]}"]=1
  fi
done

# build final lists
kept=()
removed=()
for ((i=0; i<n; i++)); do
  f=${files[i]}
  if [[ -n "${keep[$f]:-}" ]]; then
    kept+=("$f")
  else
    removed+=("$f")
  fi
done

printf '📁 KEEP LIST (%d):\n' "${#kept[@]}"
for v in "${kept[@]}"; do printf '  ✅ %s\n' "$v"; done
printf '🗑️  REMOVE LIST (%d):\n' "${#removed[@]}"
for v in "${removed[@]}"; do printf '  🗑️ %s\n' "$v"; done

# perform deletions -- remove all candidates in one single command, then verify
removed_count=0
failed=0

if (( ${#removed[@]} == 0 )); then
  printf 'ℹ️  INFO: nothing to remove\n'
else
  printf '🗑️  Attempting to remove all %d files\n' "${#removed[@]}"
  for f in "${removed[@]}"; do printf '  🗑️ %s\n' "$f"; done

  # Protect live file and unexpected names before doing anything destructive
  warn_count=0
  for f in "${removed[@]}"; do
    basef=$(basename -- "$f")
    if [[ "$basef" == "$LIVE" ]]; then
      printf '❌ FATAL: attempted to remove live file %s\n' "$f" >&2
      exit 1
    fi
    case "$basef" in
      root.key.*) ;;
      *)
        printf '⚠️  WARN: unexpected filename: %s\n' "$f"
        ((warn_count++))
        ;;
    esac
  done

  # Actually remove everything in one command; -v makes actions visible
  if (( ${#removed[@]} > 0 )); then
    rm -vf -- "${removed[@]}" || true
  fi

  # Re-check which ones were removed
  failed=0
  for f in "${removed[@]}"; do
    if [[ -e "$f" ]]; then
      printf '⚠️  STILL PRESENT: %s\n' "$f"
      ((failed++))
    else
      printf '✅ Removed: %s\n' "$f"
      ((removed_count++))
    fi
  done

  if (( warn_count > 0 )); then
    printf '⚠️  WARN: %d unexpected filenames detected (non-fatal)\n' "$warn_count"
  fi
fi

printf '📊 INFO: removed=%d failed=%d\n' "$removed_count" "$failed"
if (( failed > 0 )); then exit 2; fi
