#!/bin/bash
# rotate-unbound-rootkeys.sh
# Keeps newest N files, newest per UTC day for D days, newest per UTC month for M months.
# Deletes by default. Edit KEEP_NEWEST/DAYS/MONTHS at top to change behavior.
set -euo pipefail

# --- edit these ---
KEEP_NEWEST=5
DAYS=5
MONTHS=60
# -------------------

TARGET_DIR=/var/lib/unbound/
PATTERN='root.key.*'
LIVE=root.key

echo "CONFIG: TARGET_DIR=${TARGET_DIR} KEEP_NEWEST=${KEEP_NEWEST} DAYS=${DAYS} MONTHS=${MONTHS} (deletions enabled)"

cd "$TARGET_DIR" || { echo "FATAL: cannot chdir to $TARGET_DIR" >&2; exit 1; }

shopt -s nullglob
cands=( $PATTERN )
shopt -u nullglob

# remove live file from candidates
for i in "${!cands[@]}"; do
  if [[ "$(basename -- "${cands[i]}")" == "$LIVE" ]]; then
    unset 'cands[i]'
  fi
done

if [[ ${#cands[@]} -eq 0 ]]; then
  echo "INFO: no candidate backup files found - nothing to rotate"
  exit 0
fi

# build "epoch filename" list
entries=()
for f in "${cands[@]}"; do
  epoch=$(stat -c %Y -- "$f") || { echo "WARN: stat failed on $f"; continue; }
  entries+=("$epoch $f")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "INFO: no stat-able candidate backups found; nothing to rotate"
  exit 0
fi

# sort in memory and populate list array
sorted=$(printf '%s\n' "${entries[@]}" | sort -n)
mapfile -t list <<< "$sorted"
unset sorted

# expand into indexed arrays
n=0
declare -a files epochs
for entry in "${list[@]}"; do
  epoch=${entry%% *}
  file=${entry#* }
  ((n++))
  files[n]="$file"
  epochs[n]="${epoch%.*}"
done

# decide keeps
declare -A keep
for ((i=n; i>n-KEEP_NEWEST && i>0; i--)); do
  keep["${files[i]}"]=1
done

for ((d=0; d<DAYS; d++)); do
  target=$(date -u -d "-$d day" +%Y-%m-%d)
  best_idx=0; best_e=0
  for ((i=1; i<=n; i++)); do
    file_day=$(date -u -d "@${epochs[i]}" +%Y-%m-%d)
    if [[ "$file_day" == "$target" && "${epochs[i]}" -gt "$best_e" ]]; then
      best_e=${epochs[i]}; best_idx=$i
    fi
  done
  if (( best_idx > 0 )); then
    keep["${files[best_idx]}"]=1
  fi
done

for ((m=0; m<MONTHS; m++)); do
  target=$(date -u -d "-$m month" +%Y-%m)
  best_idx=0; best_e=0
  for ((i=1; i<=n; i++)); do
    file_mon=$(date -u -d "@${epochs[i]}" +%Y-%m)
    if [[ "$file_mon" == "$target" && "${epochs[i]}" -gt "$best_e" ]]; then
      best_e=${epochs[i]}; best_idx=$i
    fi
  done
  if (( best_idx > 0 )); then
    keep["${files[best_idx]}"]=1
  fi
done

# build final lists
kept=(); removed=()
for ((i=1; i<=n; i++)); do
  f=${files[i]}
  if [[ -n "${keep[$f]:-}" ]]; then
    kept+=("$f")
  else
    removed+=("$f")
  fi
done

echo "KEEP LIST (${#kept[@]}):"
for v in "${kept[@]}"; do echo "  $v"; done
echo "REMOVE LIST (${#removed[@]}):"
for v in "${removed[@]}"; do echo "  $v"; done

# perform deletions
removed_count=0
failed=0
for f in "${removed[@]}"; do
  basef=$(basename -- "$f")
  if [[ "$basef" == "$LIVE" ]]; then
    echo "FATAL: attempted to remove live file $f" >&2
    exit 1
  fi
  case "$basef" in
    root.key.*) ;;
    *) echo "WARN: unexpected filename: $f"; ((failed++)); continue;;
  esac

  echo "Attempting to remove $f"
  if rm -f -- "$f"; then
    echo "Removed $f"
    ((removed_count++))
  else
    echo "WARN: failed to remove $f"
    ((failed++))
  fi
done

echo "INFO: removed count=${removed_count}; failed=${failed}"
if (( failed > 0 )); then exit 2; fi
exit 0
