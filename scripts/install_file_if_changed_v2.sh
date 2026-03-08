#!/bin/sh
# install_file_if_changed_v2.sh — idempotent, atomic file installer (local → remote, remote → remote, or local → local)
# Hardened for Asus Merlin (RT-AX86U) + Ugreen (UGOS); BusyBox-friendly.
#
# Usage:
#   install_file_if_changed_v2.sh [-q|--quiet] \
#       SRC_HOST SRC_PORT SRC_PATH \
#       DST_HOST DST_PORT DST_PATH \
#       OWNER GROUP MODE
#
# Arguments:
# - SRC_HOST: source host ("" means local file read)
# - SRC_PORT: source SSH port (defaults to 22 when empty)
# - SRC_PATH: source file path (local or on SRC_HOST)
# - DST_HOST: destination host ("" means local filesystem)
# - DST_PORT: destination SSH port (defaults to 22 when empty)
# - DST_PATH: destination file path
# - OWNER/GROUP/MODE: applied to the installed file (MODE must be octal 3–4 digits)
#
# Options:
# -q, --quiet: suppress informational output (errors always printed)
#
# Guarantees:
# - Installs only when content differs (sha256 compare; early exit on match)
# - Destination update is atomic: stream → temp file → verify hash on disk → chmod/chown → mv into place
# - Race-condition safe: Uses directory-based locking on the destination path
# - No partial writes become active; temp file and locks are cleaned on failure
# - Locale-neutral hashing/parsing (LC_ALL=C) and hardened remote PATH
# - SSH multiplexing enabled (ControlPersist=1m)
#
# Exit codes:
#   0  -> Success, destination already up-to-date (no change)
#   3  -> Success, destination updated
#   2  -> Dependency missing (sha256sum on source or destination)
#   1  -> Failure (invalid args, SSH/access/IO error, hash mismatch, lock timeout)
set -eu
LC_ALL=C; export LC_ALL

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

[ "$(id -u)" -eq 0 ] || { echo "❌ Must be run as root" >&2; exit 1; }

[ -n "$SRC_PATH" ] && [ -n "$DST_PATH" ] && [ -n "$OWNER" ] && [ -n "$GROUP" ] && [ -n "$MODE" ] || {
    echo "❌ Usage: $0 SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
    exit 1
}

case "$MODE" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) echo "❌ Invalid octal mode: $MODE" >&2; exit 1 ;;
esac

: "${TMPDIR:=/tmp}"
[ -d "$TMPDIR" ] && [ -w "$TMPDIR" ] || { echo "❌ TMPDIR not writable: $TMPDIR" >&2; exit 1; }

PID="$$"
TS="$(date +%s).${PID}"

# ---------------------------------------------------------------------------
# SSH / EXECUTION WRAPPERS (Argument Boundary Policy)
# ---------------------------------------------------------------------------
MUX_SRC="$TMPDIR/.ifc_s_${PID}"
MUX_DST="$TMPDIR/.ifc_d_${PID}"
F_SRC="$TMPDIR/.ifc_src.${TS}"
F_DST="$TMPDIR/.ifc_dst.${TS}"

cleanup() {
    [ -n "$SRC_HOST" ] && [ -S "$MUX_SRC" ] && ssh -o ControlPath="$MUX_SRC" -O exit "$SRC_HOST" >/dev/null 2>&1 || true
    [ -n "$DST_HOST" ] && [ -S "$MUX_DST" ] && ssh -o ControlPath="$MUX_DST" -O exit "$DST_HOST" >/dev/null 2>&1 || true
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
            *) echo "❌ Multiplexing host mismatch: $_H" >&2; exit 1 ;;
        esac
        ssh -p "$_P" -o BatchMode=yes -o ConnectTimeout=10 \
            -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
            -o ControlMaster=auto -o ControlPath="$_MUX" -o ControlPersist=1m \
            -o LogLevel=ERROR "$_H" "$@"
    fi
}

run_on_dst() {
    if [ -z "$DST_HOST" ]; then
        sh -s -- "$@"
    else
        ssh_cmd "$DST_HOST" "$DST_PORT" sh -s -- "$@"
    fi
}

# ---------------------------------------------------------------------------
# STEP 1: PARALLEL HASH COMPARISON
# ---------------------------------------------------------------------------
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

wait "$P1" || { ec=$?; [ "$ec" -eq 2 ] && exit 2; exit 1; }
wait "$P2" || { ec=$?; [ "$ec" -eq 2 ] && exit 2; exit 1; }

SRC_HASH="$(cat "$F_SRC")"
DST_HASH="$(cat "$F_DST" 2>/dev/null || echo "")"

[ -n "$SRC_HASH" ] || { echo "❌ Source hash calculation failed" >&2; exit 1; }

if [ "$SRC_HASH" = "$DST_HASH" ]; then
    log "⚪ $DST_PATH up-to-date"
    exit 0
fi

# ---------------------------------------------------------------------------
# STEP 2: ATOMIC INSTALL WITH DESTINATION LOCK
# ---------------------------------------------------------------------------
H_SHORT="$(echo "$SRC_HASH" | cut -c1-16)"
DST_DIR="$(ssh_cmd "$DST_HOST" "$DST_PORT" dirname -- "$DST_PATH")"
BASE="$(ssh_cmd "$DST_HOST" "$DST_PORT" basename -- "$DST_PATH")"
TMP_REMOTE="$DST_DIR/.${BASE}.ifc_${H_SHORT}_${TS}"

ssh_cmd "$DST_HOST" "$DST_PORT" mkdir -p -- "$DST_DIR"
log "🔄 Updating $DST_PATH..."

if [ -z "$SRC_HOST" ]; then
    cat -- "$SRC_PATH"
else
    ssh_cmd "$SRC_HOST" "$SRC_PORT" cat -- "$SRC_PATH"
fi | run_on_dst \
    "$TMP_REMOTE" "$DST_PATH" "$OWNER" "$GROUP" "$MODE" "$SRC_HASH" <<'EOF'
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH
LC_ALL=C; export LC_ALL

tmp="$1"; dst="$2"; owner="$3"; group="$4"; mode="$5"; expected="$6"
lock="${dst}.lock"

# Mutex acquisition (mkdir is atomic)
i=0; locked=0
while [ "$i" -lt 10 ]; do
    if mkdir "$lock" 2>/dev/null; then locked=1; break; fi
    i=$((i + 1)); sleep 1
done

[ "$locked" -eq 1 ] || { echo "❌ Timeout waiting for lock: $lock" >&2; exit 1; }

trap 'rm -rf "$lock" "$tmp" 2>/dev/null' EXIT

# Atomic Write to temporary location
cat >"$tmp"

# Post-write Integrity Check
actual="$(sha256sum "$tmp" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { echo "❌ Hash mismatch" >&2; exit 1; }
[ -s "$tmp" ] || { echo "❌ Empty file written" >&2; exit 1; }

# Permissions and Atomic Swap
chown "$owner:$group" "$tmp" 2>/dev/null || chown "$owner" "$tmp" 2>/dev/null || true
chmod "$mode" "$tmp"
mv -f "$tmp" "$dst"
sync "$dst" 2>/dev/null || sync "$(dirname "$dst")" 2>/dev/null || sync

trap - EXIT
rm -rf "$lock"
EOF

exit 3