#!/bin/sh
# install_file_if_changed.sh — idempotent, atomic file installer (local → remote or remote → remote)
# Hardened for Asus Merlin (RT-AX86U) + Ugreen (UGOS); BusyBox-friendly.
#
# Usage:
#   install_file_if_changed.sh [-q|--quiet] \
#       SRC_HOST SRC_PORT SRC_PATH \
#       DST_HOST DST_PORT DST_PATH \
#       OWNER GROUP MODE
#
# Arguments:
# - SRC_HOST: source host ("" means local file read)
# - SRC_PORT: source SSH port (defaults to 22 when empty)
# - SRC_PATH: source file path (local or on SRC_HOST)
# - DST_HOST: destination host (required; remote install target)
# - DST_PORT: destination SSH port (defaults to 22 when empty)
# - DST_PATH: destination file path (on DST_HOST)
# - OWNER/GROUP/MODE: applied to the installed file (MODE must be octal 3–4 digits)
#
# Options:
# -q, --quiet: suppress informational output (errors always printed)
#
# Guarantees:
# - Installs only when content differs (sha256 compare; early exit on match)
# - Destination update is atomic: stream → temp file → verify hash on disk → chmod/chown → mv into place
# - No partial writes become active; temp file is cleaned on failure
# - Locale-neutral hashing/parsing (LC_ALL=C) and hardened remote PATH
# - SSH multiplexing enabled (ControlPersist=1m) with short ControlPath to avoid UNIX_PATH_MAX issues
# - Temporary files/sockets live under TMPDIR (default /tmp)
#
# Requirements:
# - Must be run as root (local side)
# - Non-interactive SSH (key-based) to SRC_HOST/DST_HOST as used
# - sha256sum must exist on source and destination (exit 2 if missing)
#
# Exit codes:
#   0  -> Success, destination already up-to-date (no change)
#   3  -> Success, destination updated
#   2  -> Dependency missing (sha256sum on source or destination)
#   1  -> Failure (invalid args, SSH/access/IO error, hash mismatch, permission error)
#
# CONTRACT:
# - Exit codes are stable: 0 unchanged, 3 changed, 2 missing dependency, 1 failure
# - Quiet suppresses info only; errors always printed to stderr
# - Destination is replaced atomically only after on-disk integrity verification
set -eu

# ---------------------------------------------------------------------------
# CONFIGURATION & ARGUMENTS
# ---------------------------------------------------------------------------
quiet=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -q|--quiet) quiet=1; shift ;;
        --) shift; break ;;
        -*) echo "❌ Unknown option: $1" >&2; exit 1 ;;
        *) break ;;
    esac
done

SRC_HOST="${1:-}"
SRC_PORT="${2:-22}"
SRC_PATH="${3:-}"
DST_HOST="${4:-}"
DST_PORT="${5:-22}"
DST_PATH="${6:-}"
OWNER="${7:-}"
GROUP="${8:-}"
MODE="${9:-}"

log() { [ "$quiet" -eq 0 ] && echo "📦 ifc: $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Must be run as root" >&2
    exit 1
fi

if [ -z "$SRC_PATH" ] || [ -z "$DST_HOST" ] || [ -z "$DST_PATH" ] || [ -z "$OWNER" ] || [ -z "$GROUP" ] || [ -z "$MODE" ]; then
    echo "❌ Usage: $0 [options] SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
    exit 1
fi

case "$MODE" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) echo "❌ Invalid octal mode: $MODE" >&2; exit 1 ;;
esac

: "${TMPDIR:=/tmp}"
[ -d "$TMPDIR" ] && [ -w "$TMPDIR" ] || { echo "❌ TMPDIR not writable: $TMPDIR" >&2; exit 1; }

PID="$$"
TS="$(date +%s).${PID}.$(date +%N 2>/dev/null || echo 0)"

# ---------------------------------------------------------------------------
# SSH MULTIPLEXING & CLEANUP (short ControlPath)
# ---------------------------------------------------------------------------
MUX_SRC="$TMPDIR/.ifc_s_${PID}"
MUX_DST="$TMPDIR/.ifc_d_${PID}"
F_SRC="$TMPDIR/.ifc_sh.${TS}"
F_DST="$TMPDIR/.ifc_dh.${TS}"

cleanup() {
    if [ -n "$SRC_HOST" ] && [ -S "$MUX_SRC" ]; then
        ssh -o ControlPath="$MUX_SRC" -O exit "$SRC_HOST" >/dev/null 2>&1 || true
    fi
    if [ -n "$DST_HOST" ] && [ -S "$MUX_DST" ]; then
        ssh -o ControlPath="$MUX_DST" -O exit "$DST_HOST" >/dev/null 2>&1 || true
    fi
    rm -f "$F_SRC" "$F_DST" "$MUX_SRC" "$MUX_DST"
}
trap cleanup EXIT INT TERM

ssh_cmd() {
    _H="$1"; _P="$2"; shift 2
    if [ -z "$_H" ]; then
        "$@"
    else
        case "$_H" in
            "$SRC_HOST") _MUX="$MUX_SRC" ;;
            "$DST_HOST") _MUX="$MUX_DST" ;;
            *) echo "❌ Multiplexing not configured for host: $_H" >&2; exit 1 ;;
        esac
        ssh -p "$_P" -o BatchMode=yes -o ConnectTimeout=10 \
            -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
            -o ControlMaster=auto -o ControlPath="$_MUX" -o ControlPersist=1m \
            -o LogLevel=ERROR "$_H" "$@"
    fi
}

###############################################################################
# Step 1: Parallel hashing (sha256sum required)
###############################################################################
( ssh_cmd "$SRC_HOST" "$SRC_PORT" sh -s -- "$SRC_PATH" <<'EOF'
set -eu
LC_ALL=C; export LC_ALL
command -v sha256sum >/dev/null 2>&1 || exit 2
[ -f "$1" ] || exit 1
sha256sum "$1" | awk '{print $1}'
EOF
) >"$F_SRC" & P1=$!

( ssh_cmd "$DST_HOST" "$DST_PORT" sh -s -- "$DST_PATH" <<'EOF'
set -eu
LC_ALL=C; export LC_ALL
command -v sha256sum >/dev/null 2>&1 || exit 2
if [ -f "$1" ]; then
  sha256sum "$1" | awk '{print $1}'
fi
EOF
) >"$F_DST" & P2=$!

if ! wait "$P1"; then
    ec=$?
    [ "$ec" -eq 2 ] && { echo "❌ sha256sum missing on source" >&2; exit 2; }
    echo "❌ Source access failed" >&2; exit 1
fi

if ! wait "$P2"; then
    ec=$?
    [ "$ec" -eq 2 ] && { echo "❌ sha256sum missing on destination" >&2; exit 2; }
    echo "❌ Destination access failed" >&2; exit 1
fi

SRC_HASH=$(cat "$F_SRC")
DST_HASH=$(cat "$F_DST" 2>/dev/null || echo "")

[ -n "$SRC_HASH" ] || { echo "❌ Source hash calculation failed" >&2; exit 1; }

if [ "$SRC_HASH" = "$DST_HASH" ]; then
    log "⚪ $DST_PATH up-to-date"
    exit 0
fi

###############################################################################
# Step 2: Transfer & atomic swap (verify on disk)
###############################################################################
DST_DIR=$(ssh_cmd "$DST_HOST" "$DST_PORT" dirname -- "$DST_PATH")
BASE=$(ssh_cmd "$DST_HOST" "$DST_PORT" basename -- "$DST_PATH")
SRC_HASH_SHORT=$(printf '%s' "$SRC_HASH" | cut -c1-16)
TMP_REMOTE="$DST_DIR/.${BASE}.ifc_${SRC_HASH_SHORT}_${TS}"

ssh_cmd "$DST_HOST" "$DST_PORT" mkdir -p -- "$DST_DIR"
log "🔄 Updating $DST_PATH..."

# Data stream source (local or remote) -> destination remote installer (reads stdin)
if [ -z "$SRC_HOST" ]; then
    cat -- "$SRC_PATH"
else
    ssh_cmd "$SRC_HOST" "$SRC_PORT" cat -- "$SRC_PATH"
fi | ssh_cmd "$DST_HOST" "$DST_PORT" env LC_ALL=C sh -s -- \
    "$TMP_REMOTE" "$DST_PATH" "$OWNER" "$GROUP" "$MODE" "$SRC_HASH" <<'EOF'
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
LC_ALL=C; export LC_ALL
umask 022

command -v sha256sum >/dev/null 2>&1 || { echo "❌ sha256sum missing on destination" >&2; exit 2; }

tmp="$1"; dst="$2"; owner="$3"; group="$4"; mode="$5"; expected="$6"
trap 'rm -f "$tmp" 2>/dev/null' EXIT

cat >"$tmp"

actual=$(sha256sum "$tmp" | awk '{print $1}')
[ "$actual" = "$expected" ] || { echo "❌ Hash mismatch (expected $expected, got $actual)" >&2; exit 1; }
[ -s "$tmp" ] || { echo "❌ Disk write failed or empty file" >&2; exit 1; }

chown "$owner:$group" "$tmp" 2>/dev/null || chown "$owner" "$tmp" 2>/dev/null || echo "⚠️ Ownership unchanged" >&2
chmod "$mode" "$tmp"

mv -f "$tmp" "$dst"
sync "$dst" 2>/dev/null || sync "$(dirname -- "$dst")" 2>/dev/null || sync

trap - EXIT
EOF

exit 3
