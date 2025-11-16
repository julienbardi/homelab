#!/usr/bin/env bash
# rotate-unbound-rootkeys.sh
# Keep newest N files, newest per day for D days, newest per month for M months.
# Operates only on /var/lib/unbound/root.key.* (excludes /var/lib/unbound/root.key).
#
# To install:
#   sudo cp /path/to/rotate-unbound-rootkeys.sh /usr/local/bin/rotate-unbound-rootkeys.sh
#   sudo chmod 755 /usr/local/bin/rotate-unbound-rootkeys.sh
# To run manually:
#   sudo /usr/local/bin/rotate-unbound-rootkeys.sh
set -euo pipefail

# Runtime hardening: exclusive lock to avoid concurrent runs
LOGGER_TAG=${LOGGER_TAG:-rotate-unbound-rootkeys}
LOCKFILE=${LOCKFILE:-/var/lock/rotate-unbound-rootkeys.lock}
exec 9>>"$LOCKFILE"
if ! flock -n 9; then
  logger -t "$LOGGER_TAG" "Another rotate job is running; exiting"
  exit 0
fi

# Configurable retention (can be overridden by env)
KEEP_NEWEST=${KEEP_NEWEST:-5}    # keep this many newest files as a safety net
DAYS=${DAYS:-5}                  # keep newest file per UTC day for the last N days
MONTHS=${MONTHS:-60}             # keep newest file per UTC month for the last N months
DRY_RUN=${DRY_RUN:-0}            # set to 1 to only show actions without deleting

TARGET_DIR=${TARGET_DIR:-/var/lib/unbound}
PATTERN='root.key.*'
LIVE=${LIVE:-root.key}

log(){ logger -t "$LOGGER_TAG" -- "$*"; }
die(){ logger -t "$LOGGER_TAG" -- "FATAL: $*"; exit 1; }
warn(){ logger -t "$LOGGER_TAG" -- "WARN: $*"; }

# Requirements checks
if [[ "$(id -u)" -ne 0 ]]; then die "must be run as root"; fi
if ! command -v stat >/dev/null 2>&1; then die "stat(1) required"; fi
if ! stat -c %Y / >/dev/null 2>&1; then die "stat version incompatible (expecting GNU stat)"; fi

cd "$TARGET_DIR" || die "cannot chdir to $TARGET_DIR"

if [[ ! -e "$LIVE" ]]; then warn "live anchor $TARGET_DIR/$LIVE not present; continuing"; fi

# 1) list files (shell glob), exclude LIVE (all in memory)
shopt -s nullglob
cands=( $PATTERN )
shopt -u nullglob
for i in "${!cands[@]}"; do [[ "${cands[i]}" == "$LIVE" ]] && unset 'cands[i]'; done
if [[ ${#cands[@]} -eq 0 ]]; then log "INFO: no candidate backup files found (pattern: $PATTERN) - nothing to rotate"; exit 0; fi

# 2) build entries epoch+filename and sort (oldest -> newest)
entries=()
for f in "${cands[@]}"; do
  if ! epoch=$(stat -c %Y -- "$f" 2>/dev/null); then
    warn "stat failed on $f; skipping"
    continue
  fi
  entries+=("$epoch $f")
done
if [[ ${#entries[@]} -eq 0 ]]; then log "INFO: no stat-able candidate backups found; nothing to rotate"; exit 0; fi
mapfile -t list < <(printf '%s\n' "${entries[@]}" | sort -n)
if [[ ${#list[@]} -eq 0 ]]; then log "INFO: nothing after sorting; aborting"; exit 0; fi

# 3) expand into indexed arrays (1..n) and flag keeps in memory
n=0
declare -a files epochs
for entry in "${list[@]}"; do
  epoch=${entry%% *}
  file=${entry#* }
  ((n++))
  files[n]="$file"
  epochs[n]="${epoch%.*}"
done

log "DEBUG: discovered $n candidate backups; KEEP_NEWEST=$KEEP_NEWEST DAYS=$DAYS MONTHS=$MONTHS"

declare -A keep

# keep newest KEEP_NEWEST
for ((i=n; i>n-KEEP_NEWEST && i>0; i--)); do
  keep["${files[i]}"]=1
  log "DEBUG: keep newest safety -> ${files[i]}"
done

# keep newest per UTC day for last DAYS
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

# keep newest per UTC month for last MONTHS
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

# 4) remove unflagged files one-by-one with validation
kept=(); removed=(); failed=0
for ((i=1; i<=n; i++)); do
  f=${files[i]}
  if [[ -n "${keep[$f]:-}" ]]; then
    kept+=("$f")
    continue
  fi

  # Safety: never remove LIVE and validate filename pattern
  if [[ "$f" == "$LIVE" ]]; then
    die "invariant violation: attempted to remove live file $f"
  fi
  case "$f" in
    root.key.*) ;;
    *) warn "unexpected filename not matching root.key.*: $f"; ((failed++)); continue ;;
  esac

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: would remove $f"
    removed+=("$f")
    continue
  fi

  if rm -f -- "$f"; then
    log "Removed old anchor backup: $f"
    removed+=("$f")
  else
    warn "failed to remove $f - permissions/immutable/FS?"
    ((failed++))
  fi
done

log "INFO: keep count=${#kept[@]}; remove count=${#removed[@]}; failed=$failed"

if (( failed > 0 )); then
  logger -t "$LOGGER_TAG" "rotate completed with $failed failures"
  exit 2
fi

exit 0
