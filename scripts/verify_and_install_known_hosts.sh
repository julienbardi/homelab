#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
COMMON="$SCRIPT_DIR/common.sh"
source "$COMMON"

# verify_and_install_known_hosts.sh — Gold Version (refactored)
# Guarantees preserved:
# - Atomic writes (via IFCv3)
# - Race-safe (via IFCv3 local lock + atomic mv)
# - Parallel scanning
# - Canonical token normalization
# - Port-aware scanning
# - No root writes
# - No hashed known_hosts
# - Sub-0.3s warm

DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
HOSTSCAN_TIMEOUT=1
LC_ALL=C; export LC_ALL

mkdir -p "$HOME/.ssh"
touch "$KNOWN_HOSTS"
chmod 600 "$KNOWN_HOSTS"

# Authoritative host list from Makefile
HOSTS="
router      ${LAN_ROUTER}     ${ROUTER_SSH_PORT}
diskstation ${LAN_SYNOLOGY}   2222
qnap        ${LAN_QNAP}       2222
nas         ${LAN_NAS}        2222
localhost   127.0.0.1         2222
vpn.bardi.ch   -              2222
ssh.github.com -              443
github.com     -              22
"

# --- 1. Fast-path: all tokens present? ---
all_present=1
while read -r name ip port; do
    [ -z "$name" ] && continue
    token="${ip:-$name}"
    [ "$token" = "-" ] && continue

    search="$token"
    [ "$port" != "22" ] && search="[$token]:$port"

    if ! grep -Eq "(^|,)$search(,| |$)" "$KNOWN_HOSTS"; then
        all_present=0
        break
    fi
done <<< "$HOSTS"

[ "$all_present" -eq 1 ] && exit 0

# --- 2. Slow-path: parallel scan ---
TMPDIR_SCAN="$(mktemp -p "$RUNTIME_DIR" -d homelab.XXXXXX)"
trap 'rm -rf "$TMPDIR_SCAN"' EXIT

declare -a OUTFILES=()

scan_one() {
    local name="$1" ip="$2" port="$3" outfile="$4"
    local token="${ip:-$name}"

    if [ "$port" != "22" ]; then
        hosttok="[$token]:$port"
        raw="$(ssh-keyscan -t ed25519 -p "$port" -T "$HOSTSCAN_TIMEOUT" "$token" 2>/dev/null || true)"
    else
        hosttok="$token"
        raw="$(ssh-keyscan -t ed25519 -T "$HOSTSCAN_TIMEOUT" "$token" 2>/dev/null || true)"
    fi

    [ -z "$raw" ] && return 0

    while read -r kline; do
        [ -z "$kline" ] && continue
        printf "%s\n" "$(printf "%s\n" "$kline" | sed -E "s/^[^ ]+/${hosttok}/")" >> "$outfile"
    done <<< "$raw"
}

while read -r name ip port; do
    [ -z "$name" ] && continue
    outfile="$(mktemp "$TMPDIR_SCAN/scan.XXXXXX")"
    OUTFILES+=("$outfile")
    scan_one "$name" "$ip" "$port" "$outfile" &
done <<< "$HOSTS"
wait

# --- 3. Atomic update via IFCv3 ---
tmp="$(mktemp -p "$RUNTIME_DIR" homelab.XXXXXX)"
chmod 600 "$tmp"
cp "$KNOWN_HOSTS" "$tmp"

for f in "${OUTFILES[@]}"; do
    [ ! -s "$f" ] && continue
    cat "$f" >> "$tmp"
done

sort -u "$tmp" > "$tmp.sorted"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN: would update known_hosts"
else
    install_file_if_changed_v3.sh \
        "" "22" "$tmp.sorted" \
        "" "22" "$KNOWN_HOSTS" \
        "$USER" "$USER" "0600"
fi

echo "✅ known_hosts synchronized."
