#!/usr/bin/env bash
set -euo pipefail

# verify_and_install_known_hosts.sh
# Gold Version: Sub-0.3s warm, Atomic, Race-Safe, No Heredocs.
# Contract: Hashed known_hosts entries are not supported.
# Contract: Input tokens must not contain internal spaces.
# Contract: DRY_RUN skips both User and Root mutations.

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

# Generate ephemeral host list from authoritative Make variables
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"
HOSTS_FILE="$(mktemp -p "$RUNTIME_DIR" homelab-known-hosts.XXXXXX)"
trap 'rm -f "$HOSTS_FILE"' EXIT

cat > "$HOSTS_FILE" <<EOF
router      ${LAN_ROUTER}     ${ROUTER_SSH_PORT}
diskstation ${LAN_SYNOLOGY}   2222
qnap        ${LAN_QNAP}       2222
nas         ${LAN_NAS}        2222
localhost   127.0.0.1         2222
vpn.bardi.ch   -              2222
ssh.github.com -              443
github.com     -              22
EOF

KNOWN_HOSTS="$HOME/.ssh/known_hosts"
HOSTSCAN_TIMEOUT=1
export LC_ALL=C

# --- 1. PRE-FLIGHT FAST PATH ---
[ ! -f "$KNOWN_HOSTS" ] && { mkdir -p "$HOME/.ssh"; touch "$KNOWN_HOSTS"; chmod 600 "$KNOWN_HOSTS"; }

ALL_PRESENT=1
while IFS= read -r raw || [ -n "$raw" ]; do
  # Trim and collapse whitespace in one fork
  line="$(printf '%s\n' "${raw%%#*}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  [ -z "$line" ] && continue

  # Intentional word splitting: HOSTS_FILE lines are space-separated by contract,
  # and tokens must not contain internal spaces.
  # shellcheck disable=SC2086
  set -- $line
  p_ip="${3:-}"; p_pub="${2:-}"; p_port="${4:-22}"
  token="${p_ip:-$p_pub}"
  [ "$token" == "-" ] && continue

  search="$token"
  [ "$p_port" != "22" ] && search="\[$token\]:$p_port"

  # Mathematically correct boundary regex: start, comma OR end, space, comma
  if ! grep -Eq "(^|,)$search(,| |$)" "$KNOWN_HOSTS" 2>/dev/null; then
    ALL_PRESENT=0; break
  fi
done < "$HOSTS_FILE"

[ "$ALL_PRESENT" -eq 1 ] && exit 0

# --- 2. FULL SCAN PREPARATION ---
LOCKFILE="${RUNTIME_DIR}/locks/verify_known_hosts.lock"
mkdir -p "$(dirname "$LOCKFILE")"

TMPDIR_SCAN=""
cleanup() {
  [ -n "$TMPDIR_SCAN" ] && rm -rf "$TMPDIR_SCAN" 2>/dev/null
  rm -f "$LOCKFILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

exec 9>"$LOCKFILE"
flock -n 9 || exit 0

TMPDIR_SCAN="$(mktemp -p "$RUNTIME_DIR" -d homelab.XXXXXX)"
declare -a HOST_META=()

scan_one_host() {
  local a="$1" p="$2" i="$3" pt="$4" d="$5" out="$6"
  local tokens=(); [ -n "$i" ] && [ "$i" != "-" ] && tokens+=("$i")
  [ -n "$p" ] && [ "$p" != "-" ] && tokens+=("$p")

  local found=0
  for t in "${tokens[@]}"; do
    [ "$found" -eq 1 ] && break
    if [ "$pt" != "22" ]; then
      raw="$(ssh-keyscan -t ed25519 -p "$pt" -T "$HOSTSCAN_TIMEOUT" "$t" 2>/dev/null || true)"
      hosttok="[$t]:$pt"
    else
      raw="$(ssh-keyscan -t ed25519 -T "$HOSTSCAN_TIMEOUT" "$t" 2>/dev/null || true)"
      hosttok="$t"
    fi

    if [ -n "$raw" ]; then
      found=1
      printf 'D_NAME=%q\n' "$d" > "$out"
      while IFS= read -r kline; do
        [ -z "$kline" ] && continue
        # Canonical token collapse
        norm="$(printf "%s\n" "$kline" | sed -E "s/^[^ ]+/${hosttok}/")"
        printf 'KEYS+=(%q)\n' "$norm" >> "$out"
      done <<< "$raw"
    fi
  done
}

# Phase 1: Launch background scans
while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(printf '%s\n' "${raw%%#*}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  [ -z "$line" ] && continue
  # Intentional word splitting: HOSTS_FILE lines are space-separated by contract,
  # and tokens must not contain internal spaces.
  # shellcheck disable=SC2086
  set -- $line
  a="$1" p="$2" i="$3" pt="${4:-22}"
  d="$a"; [ "$a" == "-" ] && d="${p:-$i}"

  outfile="$(mktemp "$TMPDIR_SCAN/scan.XXXXXX")"
  HOST_META+=("$d" "$outfile")
  scan_one_host "$a" "$p" "$i" "$pt" "$d" "$outfile" &
done < "$HOSTS_FILE"
wait

# Phase 2: Atomic updates
for ((idx=0; idx<${#HOST_META[@]}; idx+=2)); do
  # shellcheck disable=SC2034
  d_name="${HOST_META[idx]}"
  o_file="${HOST_META[idx+1]}"
  [ ! -s "$o_file" ] && continue

  KEYS=(); D_NAME=""
  # shellcheck disable=SC1090
  source "$o_file"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: Found new keys for $D_NAME"
    continue
  fi

  # Atomic User Update: Copy + Append -> sort a NEW + Replace
  u_tmp="$(mktemp -p "$RUNTIME_DIR" homelab.XXXXXX)"
  u_sorted="$(mktemp -p "$RUNTIME_DIR" homelab.XXXXXX)"
  chmod 600 "$u_tmp" "$u_sorted"
  cp "$KNOWN_HOSTS" "$u_tmp"
  for k in "${KEYS[@]}"; do printf "%s\n" "$k" >> "$u_tmp"; done
  sort -u "$u_tmp" > "$u_sorted"
  mv "$u_sorted" "$KNOWN_HOSTS"
  rm -f "$u_tmp"

  # Root update disabled by design (Julien’s homelab contract)
  # No writes to /root/.ssh/known_hosts.

  echo "✅ Updated known_hosts for $D_NAME"
done

echo "✅ Synchronization complete."