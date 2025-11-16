#!/bin/bash
# rotate-unbound-rootkeys.sh
# Keep newest N files, newest per day for D days, newest per month for M months.
# Operates only on /var/lib/unbound/root.key.* (excludes /var/lib/unbound/root.key).
#
# To install:
#   sudo cp /home/julie/homelab/10.89.12.4/usr/local/bin/rotate-unbound-rootkeys.sh /usr/local/bin/rotate-unbound-rootkeys.sh
#   sudo chmod 755 /usr/local/bin/rotate-unbound-rootkeys.sh
# To run manually:
#   sudo /usr/local/bin/rotate-unbound-rootkeys.sh
set -euo pipefail

# --- Edit these variables directly in the script ---
KEEP_NEWEST=5        # keep this many newest files as a safety net
DAYS=5               # keep newest file per UTC day for the last N days
MONTHS=60            # keep newest file per UTC month for the last N months
DRY_RUN=1            # safe default: 1 => preview only. Set to 0 to enable deletions.
# ---------------------------------------------------

TARGET_DIR=/var/lib/unbound/
PATTERN='root.key.*'
LIVE=root.key

# plain terminal output
out(){ printf '%s\n' "$*"; }
die(){ printf 'FATAL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'WARN: %s\n' "$*"; }

# require bash >= 4 for associative arrays
_major=${BASH_VERSINFO[0]:-0}
if (( _major < 4 )); then
  die "bash >= 4 required (found $BASH_VERSION)"
fi

if [[ "$(id -u)" -ne 0 ]]; then die "must be run as root"; fi
if ! command -v stat >/dev/null 2>&1; then die "stat(1) required"; fi
if ! stat -c %Y / >/dev/null 2>&1; then die "stat version incompatible (expecting GNU stat)"; fi

# CLI: only --dry-run supported (overrides in-script default)
CLI_DRY_RUN=""
while [[ ${1:-} != "" ]]; do
  case "$1" in
    --dry-run) CLI_DRY_RUN=1; shift ;;
    --help) printf 'Usage: %s [--dry-run]\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; printf 'Usage: %s [--dry-run]\n' "$0" >&2; exit 2 ;;
  esac
done
if [[ -n "$CLI_DRY_RUN" ]]; then DRY_RUN=1; fi

out "CONFIG: TARGET_DIR=${TARGET_DIR} KEEP_NEWEST=${KEEP_NEWEST} DAYS=${DAYS} MONTHS=${MONTHS} DRY_RUN=${DRY_RUN}"

cd "$TARGET_DIR" || die "cannot chdir to $TARGET_DIR"

if [[ ! -e "$LIVE" ]]; then warn "live anchor ${TARGET_DIR}${LIVE} not present; continuing"; fi

# 1) list files
shopt -s nullglob
cands=( $PATTERN )
shopt -u nullglob

# remove any candidate whose basename is the live file
for i in "${!cands[@]}"; do
  if [[ "$(basename -- "${cands[i]}")" == "$LIVE" ]]; then
    unset 'cands[i]'
  fi
done

if [[ ${#cands[@]} -eq 0 ]]; then
  out "INFO: no candidate backup files found (pattern: $PATTERN) - nothing to rotate"
  exit 0
fi

# 2) build epoch+filename list and sort
entries=()
for f in "${cands[@]}"; do
  if ! epoch=$(stat -c %Y -- "$f" 2>/dev/null); then
    warn "stat failed on $f; skipping"
    continue
  fi
  entries+=("$epoch $f")
done

if [[ ${#entries[@]} -eq 0 ]]; then
  out "INFO: no stat-able candidate backups found; nothing to rotate"
  exit 0
fi

mapfile -t list < <(printf '%s\n' "${entries[@]}" | sort -n)

if [[ ${#list[@]} -eq 0 ]]; then
  out "INFO: nothing after sorting; aborting"
  exit 0
fi

# 3) expand and choose keeps
n=0
declare -a files epochs
for entry in "${list[@]}"; do
  epoch=${entry%% *}
  file=${entry#* }
  ((n++))
  files[n]="$file"
  epochs[n]="${epoch%.*}"
done

out "DEBUG: discovered $n candidate backups; KEEP_NEWEST=$KEEP_NEWEST DAYS=$DAYS MONTHS=$MONTHS"

declare -A keep

# newest KEEP_NEWEST
for ((i=n; i>n-KEEP_NEWEST && i>0; i--)); do
  keep["${files[i]}"]=1
  out "DEBUG: keep newest safety -> ${files[i]}"
done

# newest per UTC day
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
    out "DEBUG: keep newest for day $target -> ${files[best_idx]}"
  fi
done

# newest per UTC month
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
    out "DEBUG: keep newest for month $target -> ${files[best_idx]}"
  fi
done

# build KEEP and REMOVE lists
kept=(); removed=()
for ((i=1; i<=n; i++)); do
  f=${files[i]}
  if [[ -n "${keep[$f]:-}" ]]; then
    kept+=("$f")
  else
    removed+=("$f")
  fi
done

# print lists
out "KEEP LIST (${#kept[@]}):"
for v in "${kept[@]}"; do out "  $v"; done
out "REMOVE LIST (${#removed[@]}):"
for v in "${removed[@]}"; do out "  $v"; done

# stop if dry
if [[ "$DRY_RUN" == "1" ]]; then
  out "DRY_RUN=1 active; no files will be deleted. Run with no --dry-run (or edit DRY_RUN=0) to enable deletions."
  exit 0
fi

# perform deletions (non-interactive)
failed=0
removed_count=0
for f in "${removed[@]}"; do
  basef=$(basename -- "$f")
  if [[ "$basef" == "$LIVE" ]]; then
    die "invariant violation: attempted to remove live file $f"
  fi
  case "$basef" in
    root.key.*) ;;
    *)
      warn "unexpected filename not matching root.key.*: $f"
      ((failed++))
      continue
      ;;
  esac

  out "Attempting to remove $f"
  if rm -f -- "$f"; then
    out "Removed $f"
    ((removed_count++))
  else
    warn "failed to remove $f"
    warn "ls -l output:"
    ls -l -- "$f" 2>/dev/null || true
    if command -v lsattr >/dev/null 2>&1; then
      warn "lsattr output:"
      lsattr -- "$f" 2>/dev/null || true
    fi
    warn "Suggested remediation: sudo chattr -i -- \"$f\""
    ((failed++))
  fi
done

out "INFO: removed count=${removed_count}; failed=${failed}"

if (( failed > 0 )); then
  exit 2
fi

exit 0
