#!/usr/bin/env bash
# rotate-unbound-rootkeys.sh
# Keep newest N files, newest per day for D days, newest per month for M months.
# Operates only on /var/lib/unbound/root.key.* (excludes /var/lib/unbound/root.key).
#
# To install:
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/rotate-unbound-rootkeys.sh /usr/local/bin/rotate-unbound-rootkeys.sh; sudo chmod 755 /usr/local/bin/rotate-unbound-rootkeys.sh
# To run manually:
#   sudo /usr/local/bin/rotate-unbound-rootkeys.sh
set -euo pipefail

# Configurable retention (edit here)
KEEP_NEWEST=5    # keep this many newest files as a safety net
DAYS=5           # keep newest file per UTC day for the last N days
MONTHS=60        # keep newest file per UTC month for the last N months

TARGET_DIR=/var/lib/unbound
PATTERN='root.key.*'
LIVE='root.key'

cd "$TARGET_DIR" || exit 0

# fast exit if no candidates
shopt -s nullglob
candidates=( $PATTERN )
shopt -u nullglob
if [[ ${#candidates[@]} -eq 0 ]]; then
  exit 0
fi

# Produce sorted list: epoch filename (oldest -> newest)
mapfile -t list < <(find . -maxdepth 1 -type f -name "$PATTERN" ! -name "$LIVE" -printf '%T@ %p\n' 2>/dev/null | sort -n)

# Build arrays of filenames and epochs
n=0
for line in "${list[@]}"; do
  epoch=${line%% *}
  file=${line#* }
  file=${file#./}
  ((n++))
  files[n]="$file"
  epochs[n]="${epoch%.*}"
done

declare -A keep
now=$(date -u +%s)

# 1) keep KEEP_NEWEST newest
for ((i=n;i>n-KEEP_NEWEST && i>0;i--)); do
  keep["${files[i]}"]=1
done

# 2) keep newest per day for last DAYS (UTC)
for ((d=0; d<DAYS; d++)); do
  target=$(date -u -d "-$d day" +%Y-%m-%d)
  best_idx=0; best_e=0
  for ((i=1;i<=n;i++)); do
    file_day=$(date -u -d "@${epochs[i]}" +%Y-%m-%d)
    if [[ "$file_day" == "$target" && "${epochs[i]}" -gt "$best_e" ]]; then
      best_e=${epochs[i]}; best_idx=$i
    fi
  done
  (( best_idx > 0 )) && keep["${files[best_idx]}"]=1
done

# 3) keep newest per month for last MONTHS (UTC)
for ((m=0; m<MONTHS; m++)); do
  # use 30-day offset as anchor for month calculation
  target=$(date -u -d "-$m month" +%Y-%m)
  best_idx=0; best_e=0
  for ((i=1;i<=n;i++)); do
    file_mon=$(date -u -d "@${epochs[i]}" +%Y-%m)
    if [[ "$file_mon" == "$target" && "${epochs[i]}" -gt "$best_e" ]]; then
      best_e=${epochs[i]}; best_idx=$i
    fi
  done
  (( best_idx > 0 )) && keep["${files[best_idx]}"]=1
done

# Remove files not marked to keep (never touch live root.key)
# Remove files not marked to keep (never touch live root.key)
for ((i=1;i<=n;i++)); do
  f=${files[i]}
  if [[ -z "${keep[$f]:-}" ]]; then
    if rm -f -- "$f"; then
      logger -t rotate-unbound-rootkeys "Removed old anchor backup: $f"
    else
      logger -t rotate-unbound-rootkeys "Failed to remove old anchor backup: $f (check permissions/immutable bit/FS)"
    fi
  fi
done

exit 0
