#!/usr/bin/env bash
# rotate-unbound-rootkeys.sh
# Keeps newest N files, newest per UTC day for D days, newest per UTC month for M months.
# Deletes by default. Edit KEEP_NEWEST/DAYS/MONTHS at top to change behavior.
set -euo pipefail

# --- edit these ---
KEEP_NEWEST=5
DAYS=5
MONTHS=60
# -------------------

TARGET_DIR=/var/lib/unbound
PATTERN='root.key.*'
LIVE='root.key'

echo "CONFIG: TARGET_DIR=${TARGET_DIR} KEEP_NEWEST=${KEEP_NEWEST} DAYS=${DAYS} MONTHS=${MONTHS} (deletions enabled)"

cd -- "$TARGET_DIR" || { echo "FATAL: cannot chdir to $TARGET_DIR" >&2; exit 1; }

# collect candidates with a safe glob expansion into an array
shopt -s nullglob
mapfile -t cands < <(printf '%s\0' $PATTERN | xargs -0 -n1 printf '%s\n') || true
shopt -u nullglob

# remove live file from candidates (handle full names)
filtered=()
for f in "${cands[@]}"; do
  if [[ "$(basename -- "$f")" == "$LIVE" ]]; then
    echo "DEBUG: skipping live file $f"
    continue
  fi
  filtered+=("$f")
done
cands=("${filtered[@]}")

if [[ ${#cands[@]} -eq 0 ]]; then
  echo "INFO: no candidate backup files found - nothing to rotate"
  exit 0
fi

# build list of "epoch<tab>file" safely
entries=()
for f in "${cands[@]}"; do
  if ! epoch=$(stat -c %Y -- "$f" 2>/dev/null); then
    echo "WARN: stat failed on '$f' - skipping"
    continue
  fi
  entries+=("$epoch"$'\t'"$f")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "INFO: no stat-able candidate backups found; nothing to rotate"
  exit 0
fi

# sort by epoch numeric ascending (oldest first)
IFS=$'\n' sorted=($(printf '%s\n' "${entries[@]}" | sort -n -t$'\t' -k1,1)) ; unset IFS

# expand into 0-based arrays
files=()
epochs=()
for item in "${sorted[@]}"; do
  epoch=${item%%$'\t'*}
  file=${item#*$'\t'}
  files+=("$file")
  epochs+=("$epoch")
done
n=${#files[@]}
if (( n == 0 )); then
  echo "INFO: nothing to process after sorting; exiting"
  exit 0
fi

declare -A keep
# keep newest N (iterate from newest)
for ((i=n-1; i>=0 && i>n-1-KEEP_NEWEST; i--)); do
  keep["${files[i]}"]=1
done

# keep newest per UTC day for DAYS
for ((d=0; d<DAYS; d++)); do
  target=$(date -u -d "-$d day" +%Y-%m-%d)
  best_idx=-1
  best_e=0
  for ((i=0; i<n; i++)); do
    # guard: skip empty epoch
    e=${epochs[i]:-0}
    # date -u -d "@$e" will fail if e is not numeric; guard that
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

# keep newest per UTC month for MONTHS
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

# build final kept and removed lists
kept=()
removed=()
for f in "${files[@]}"; do
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
