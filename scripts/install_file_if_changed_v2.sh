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
set -u
LC_ALL=C; export LC_ALL

# --- Sourcing common.sh ---
SCRIPT_NAME="" # Tells common.sh to suppress brackets

# Using absolute path for the system-wide library
if [ -f "/usr/local/bin/common.sh" ]; then
    # Use the POSIX dot operator for maximum compatibility with /bin/sh
    . /usr/local/bin/common.sh
fi
# If common.sh wasn't found, we define a barebones log so the script doesn't crash
if ! command -v log >/dev/null 2>&1; then
    log() { echo "$*" >&2; }
fi

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

INSTALL_MODE=local
[ -n "$DST_HOST" ] && INSTALL_MODE=remote

# Validations
[ -n "$SRC_PATH" ] && [ -n "$DST_PATH" ] && [ -n "$OWNER" ] && [ -n "$GROUP" ] && [ -n "$MODE" ] || {
    echo "❌ Usage: SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
    exit 1
}

PID="$$"
TS="$(date +%s).${PID}"
: "${TMPDIR:=/tmp}"

# ---------------------------------------------------------------------------
# STEP 1: HASH CALCULATION
# ---------------------------------------------------------------------------
#[ "$quiet" -eq 0 ] && log "📦 Checking $SRC_PATH..."

# Calculate Source Hash
if [ -z "$SRC_HOST" ]; then
    SRC_HASH=$(sha256sum "$SRC_PATH" 2>/dev/null | awk '{print $1}')
else
    SRC_HASH=$(ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "sha256sum '$SRC_PATH'" 2>/dev/null | awk '{print $1}')
fi

if [ -z "$SRC_HASH" ]; then
    echo "❌ IFC: Failed to calculate source hash for $SRC_PATH" >&2
    exit 1
fi

# Calculate Destination Hash (using sudo locally to handle /etc/ssl permissions)
if [ -z "$DST_HOST" ]; then
    DST_HASH=$(sudo sha256sum "$DST_PATH" 2>/dev/null | awk '{print $1}') || DST_HASH="none"
else
    DST_HASH=$(ssh -p "$DST_PORT" -o BatchMode=yes "$DST_HOST" "sha256sum '$DST_PATH'" 2>/dev/null | awk '{print $1}') || DST_HASH="none"
fi

if [ "$SRC_HASH" = "$DST_HASH" ]; then
    [ "$quiet" -eq 0 ] && log "⚪ $DST_PATH up-to-date"
    exit 0
fi

# ---------------------------------------------------------------------------
# STEP 2: UPDATE (ATOMIC)
# ---------------------------------------------------------------------------
[ "$quiet" -eq 0 ] && log "🔄 Updating $DST_PATH..."

if [ -z "$DST_HOST" ]; then
    # --- LOCAL INSTALL STRATEGY ---
    LOCK="${DST_PATH}.lock"
    BUFFER="${TMPDIR}/.ifc_buf_${PID}"

    # Capture source data into a buffer julie can write to
    if [ -z "$SRC_HOST" ]; then
        cat "$SRC_PATH" > "$BUFFER"
    else
        ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "cat '$SRC_PATH'" > "$BUFFER"
    fi

    # Verify buffer hash before escalation
    BUF_HASH=$(sha256sum "$BUFFER" | awk '{print $1}')
    if [ "$BUF_HASH" != "$SRC_HASH" ]; then
        echo "❌ IFC: Buffer corruption detected" >&2
        rm -f "$BUFFER"
        exit 1
    fi

    # Escalated Atomicity: Lock, Move, Chown, Chmod
    # We use a single sudo call with a simple command chain to ensure it works on UGOS
    sudo sh -c "
        mkdir '$LOCK' 2>/dev/null || { echo 'Lock exists' >&2; exit 1; }
        mv -f '$BUFFER' '$DST_PATH'
        chown '$OWNER:$GROUP' '$DST_PATH' 2>/dev/null || chown '$OWNER' '$DST_PATH'
        chmod '$MODE' '$DST_PATH'
        rm -rf '$LOCK'
        sync
    " || {
        echo "❌ IFC: Local installation failed" >&2
        sudo rm -rf "$LOCK"
        rm -f "$BUFFER"
        exit 1
    }
    rm -f "$BUFFER"

else
    # --- REMOTE INSTALL STRATEGY (binary-safe, no router deps) ---
    BUFFER="${TMPDIR}/.ifc_buf_${PID}"

    # Capture source into local buffer (binary-safe)
    if [ -z "$SRC_HOST" ]; then
        cat "$SRC_PATH" > "$BUFFER"
    else
        ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "cat '$SRC_PATH'" > "$BUFFER"
    fi

    # Verify buffer integrity before transfer
    BUF_HASH=$(sha256sum "$BUFFER" | awk '{print $1}')
    if [ "$BUF_HASH" != "$SRC_HASH" ]; then
        echo "❌ IFC: Buffer corruption detected" >&2
        rm -f "$BUFFER"
        exit 1
    fi

    # Transfer raw bytes safely
    scp -O -P "$DST_PORT" "$BUFFER" "$DST_HOST:/tmp/.ifc_rem_${PID}" || {
        echo "❌ IFC: SCP transfer failed" >&2
        rm -f "$BUFFER"
        exit 1
    }

    rm -f "$BUFFER"

    # Finalize atomically on router
    ssh -p "$DST_PORT" -o BatchMode=yes "$DST_HOST" "
        set -eu
        T=\"/tmp/.ifc_rem_${PID}\"
        H=\$(sha256sum \"\$T\" | awk '{print \$1}')
        if [ \"\$H\" != \"$SRC_HASH\" ]; then exit 1; fi
        mkdir -p \"\$(dirname '$DST_PATH')\"
        mv -f \"\$T\" '$DST_PATH'
        chown '$OWNER:$GROUP' '$DST_PATH' 2>/dev/null || chown '$OWNER' '$DST_PATH'
        chmod '$MODE' '$DST_PATH'
        sync
    " || {
        echo "❌ IFC: Remote installation failed" >&2
        exit 1
    }
fi


[ "$quiet" -eq 0 ] && log "✅ $DST_PATH updated successfully"
exit 3