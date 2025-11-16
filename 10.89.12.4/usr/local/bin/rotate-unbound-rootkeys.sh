#!/usr/bin/env bash
# rotate-unbound-rootkeys.sh
# Keep newest N files, newest per day for D days, newest per month for M months.
# Operates only on /var/lib/unbound/root.key.* (excludes /var/lib/unbound/root.key).
#
# To install:
#   sudo cp /home/julie/homelab/.../rotate-unbound-rootkeys.sh /usr/local/bin/rotate-unbound-rootkeys.sh
#   sudo chmod 755 /usr/local/bin/rotate-unbound-rootkeys.sh
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
LOGGER_TAG='rotate-unbound-rootkeys'

# helpers
log()   { logger -t "$LOGGER_TAG" -- "$*"; }
die()   { log "FATAL: $*"; exit 1; }

# Safety: require root
if [[ "$(id -u)" -ne 0 ]]; then
  die "must be run as root"
fi

# Ensure target directory is accessible
cd "$TARGET_DIR" || die "cannot chdir to $TARGET_DIR"

# Log missing live file but continue (we never remove LIVE)
if [[ ! -e "$LIVE" ]]; then
  log "WARN: live anchor $TARGET_DIR/$LIVE not present; continuing"
fi

# ------------------ Build sorted list (oldest -> newest) safely ------------------
# Use shell glob to gather candidates, explicitly exclude the live file.
shopt -s nullglob
cands=( root.key.* )
shopt -u nullglob

for i in "${!cands[@]}"; do
  [[ "${cands[i]}" == "$LIVE" ]] && unset 'cands[i]'
done

if [[ ${#cands[@]} -eq 0 ]]; then
  log "INFO: no candidate backup files found (pattern: $PATTERN) - nothing to rotate"
  exit 0
fi

# Build "epoch filename" entries in-memory, sort numerically, then read back into array.
entries=()
for f in "${cands[@]}"; do
  # stat -c %Y returns integer seconds since epoch on Linux; treat failure gracefully
  if ! epoch=$(stat -c %Y -- "$f" 2>/dev/null); then
    log "WARN: stat failed on $f; skipping"
    continue
  fi
  entries+=("$epoch $f")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  log "INFO: no stat-able candidate backups found; nothing to rotate"
  exit 0
fi

# Sort entries numerically (oldest -> newest) and read into list array
list=()
# Use printf to preserve whitespace and avoid subshell read races
# The while-read is in the current shell so list is populated deterministically
printf '%s\n' "${entries[@]}" | sort -n | while IFS= read -r line; do
  list+=("$line")
done

if [[ ${#list[@]} -eq 0 ]]; then
  log "INFO: nothing after sorting; aborting"
  exit 0
fi
# -------------------------------------------------------------------------------

# Expand into indexed arrays (1..n)
n=0
declare -a files
declare -a epochs
for entry in "${list[@]}"; do
  epoch=${entry%% *}
  file=${entry#* }
  file=${file#./}
  ((n++))
  files[n]="$file"
  epochs[n]="${epoch%.*}"
done

log "DEBUG: discovered $n candidate backups; KEEP_NEWEST=$KEEP_NEWEST DAYS=$DAYS MONTHS=$MONTHS"

# Build keep set
declare -A keep
now=$(date -u +%s)

# 1) keep KEEP_NEWEST newest
for ((i=n; i>n-KEEP_NEWEST && i>0; i--)); do
  keep["${files[i]}"]=1
  log "DEBUG: keep newest safety -> ${files[i]}"
done

# 2) keep newest per UTC day for last DAYS
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
    log "DEBUG: keep newest for day $target -> ${files[best_idx]}"
  fi
done

# 3) keep newest per UTC month for last MONTHS
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
    log "DEBUG: keep newest for month $target -> ${files[best_idx]}"
  fi
done

# Final decision lists
kept=()
removed=()
for ((i=1; i<=n; i++)); do
  f=${files[i]}
  if [[ -n "${keep[$f]:-}" ]]; then
    kept+=("$f")
  else
    removed+=("$f")
  fi
done

log "INFO: keep count=${#kept[@]}; remove count=${#removed[@]}"
if [[ ${#removed[@]} -eq 0 ]]; then
  log "INFO: nothing to remove after retention rules"
  exit 0
fi

# Final safety checks before removal
for f in "${removed[@]}"; do
  if [[ "$f" == "$LIVE" ]]; then
    die "invariant violation: attempted to remove live file $f"
  fi
done

# Removal with per-file logging and clear failure handling
any_failed=0
for f in "${removed[@]}"; do
  case "$f" in
    root.key.*) ;;
    *) log "ERROR: unexpected filename not matching root.key.*: $f"; any_failed=1; continue ;;
  esac

  if rm -f -- "$f"; then
    log "Removed old anchor backup: $f"
  else
    log "ERROR: failed