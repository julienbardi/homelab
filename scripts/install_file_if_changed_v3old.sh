#!/bin/sh
# install_file_if_changed_v3.sh — portable, zero-bootstrap, atomic file installer
# Usage:
#   install_file_if_changed_v3.sh [-q|--quiet] \
#       SRC_HOST SRC_PORT SRC_PATH \
#       DST_HOST DST_PORT DST_PATH \
#       OWNER GROUP MODE
# MODE may be passed as "755" or "0755"; normalize consistently

set -u
LC_ALL=C; export LC_ALL

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

[ -n "$SRC_PATH" ] && [ -n "$DST_PATH" ] && [ -n "$OWNER" ] && [ -n "$GROUP" ] && [ -n "$MODE" ] || {
    echo "❌ Usage: SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
    exit 1
}

PID="$$"
: "${TMPDIR:=/tmp}"

# Resolve SSH identity: prefer SUDO_USER's key when running under sudo
SSH_IDENTITY="$HOME/.ssh/id_ed25519"
if [ -n "${SUDO_USER:-}" ] && [ -f "/home/${SUDO_USER}/.ssh/id_ed25519" ]; then
    SSH_IDENTITY="/home/${SUDO_USER}/.ssh/id_ed25519"
fi

log() {
    [ "$quiet" -eq 0 ] && echo "$*" >&2
}

# --- 1. Source hash ---
if [ -z "$SRC_HOST" ]; then
    SRC_HASH=$(sha256sum "$SRC_PATH" 2>/dev/null | awk '{print $1}')
else
    SRC_HASH=$(ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "sha256sum '$SRC_PATH'" 2>/dev/null | awk '{print $1}')
fi

[ -n "$SRC_HASH" ] || {
    echo "❌ Failed to calculate source hash for $SRC_PATH" >&2
    exit 1
}

# --- 2. Destination hash ---
if [ -z "$DST_HOST" ]; then
    DST_HASH=$(sha256sum "$DST_PATH" 2>/dev/null | awk '{print $1}') || DST_HASH="none"
else
    # Destination hash (remote)
    DST_HASH=$(
    ssh -p "$DST_PORT" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o IdentityFile="$SSH_IDENTITY" \
        "$DST_HOST" "sha256sum '$DST_PATH' 2>/dev/null" 2>/dev/null \
    | awk '{print $1}'
    ) || DST_HASH="none"
fi

# Initialize flags
content_drift=0
owner_drift=0
group_drift=0
mode_drift=0

# Content drift (local or remote)
[ "$SRC_HASH" != "$DST_HASH" ] && content_drift=1

# Metadata drift (local only because remote metadata cannot be reliably read)
if [ -z "$DST_HOST" ]; then
    dst_owner="$(stat -c %u "$DST_PATH" 2>/dev/null || echo "")"
    dst_group="$(stat -c %g "$DST_PATH" 2>/dev/null || echo "")"
    dst_mode="$(stat -c %a "$DST_PATH" 2>/dev/null || echo "")"

    [ "$dst_owner" != "$OWNER" ] && owner_drift=1
    [ "$dst_group" != "$GROUP" ] && group_drift=1

    # Normalize both modes by stripping leading zeros (dash + BusyBox safe) and  stripping whitespaces (BusyBox)
    norm_dst_mode=$(printf "%s" "$dst_mode" | tr -d '[:space:]' | sed 's/^0*//')
    norm_req_mode=$(printf "%s" "$MODE"     | tr -d '[:space:]' | sed 's/^0*//')

    # Empty means zero
    [ -z "$norm_dst_mode" ] && norm_dst_mode=0
    [ -z "$norm_req_mode" ] && norm_req_mode=0

    [ "$norm_dst_mode" != "$norm_req_mode" ] && mode_drift=1
fi

if [ "$content_drift" = 0 ] && \
   [ "$owner_drift" = 0 ] && \
   [ "$group_drift" = 0 ] && \
   [ "$mode_drift"  = 0 ]; then
    log "🟢 already up-to-date: $DST_PATH"
    exit 0
fi

#log "🔄 updating $DST_PATH..."

# --- 3. Local buffer (always) ---
BUFFER="${TMPDIR}/.ifc_v3_${PID}_$$"

if [ -z "$SRC_HOST" ]; then
    cat "$SRC_PATH" > "$BUFFER"
else
    ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "cat '$SRC_PATH'" > "$BUFFER"
fi

BUF_HASH=$(sha256sum "$BUFFER" | awk '{print $1}')
if [ "$BUF_HASH" != "$SRC_HASH" ]; then
    echo "❌ buffer corruption detected" >&2
    rm -f "$BUFFER"
    exit 1
fi

# --- 4. Local or remote install ---
if [ -z "$DST_HOST" ]; then
    # Local atomic install
    DST_DIR=$(dirname "$DST_PATH")
    LOCK="${DST_PATH}.lock"

    mkdir -p "$DST_DIR"

    # Ensure lock + buffer are always cleaned up
    trap 'rm -rf "$LOCK" "$BUFFER" 2>/dev/null || true' EXIT

    if ! mkdir "$LOCK" 2>/dev/null; then
        echo "❌ lock held: $LOCK" >&2
        rm -f "$BUFFER"
        exit 1
    fi

    # Apply metadata (portable mode: ignore failures)
    chown "$OWNER:$GROUP" "$BUFFER" 2>/dev/null || chown "$OWNER" "$BUFFER" 2>/dev/null || true
    chmod "$MODE" "$BUFFER" 2>/dev/null || true

    if mv -f "$BUFFER" "$DST_PATH"; then
        rm -rf "$LOCK"
        sync || true
    else
        echo "❌ atomic move failed" >&2
        rm -rf "$LOCK"
        rm -f "$BUFFER"
        exit 1
    fi
else
    # Remote atomic install via SSH only
    IFC_ID="$(date +%s).$$"
    REM_DIR="$(dirname "$DST_PATH")"
    REM_TMP="$REM_DIR/.ifc_v3_${IFC_ID}"

    # Stream buffer safely (BusyBox‑safe)
    ssh -p "$DST_PORT" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o IdentityFile="$SSH_IDENTITY" \
        "$DST_HOST" "cat > '$REM_TMP'" < "$BUFFER" \
        || {
            echo "❌ remote transfer failed" >&2
            rm -f "$BUFFER"
            exit 1
        }

    rm -f "$BUFFER"

    # Remote finalize (NAS-authoritative, no remote hash)
    ssh -p "$DST_PORT" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o IdentityFile="$SSH_IDENTITY" \
        "$DST_HOST" "
            set -eu
            T='$REM_TMP'
            DST='$DST_PATH'
            OWNER='$OWNER'
            GROUP='$GROUP'
            MODE='$MODE'

            [ -f \"\$T\" ] || { echo '❌ IFCv3[remote]: temp missing' >&2; exit 1; }

            mkdir -p \"\$(dirname \"\$DST\")\" 2>/dev/null || true

            chown \"\$OWNER:\$GROUP\" \"\$T\" 2>/dev/null || chown \"\$OWNER\" \"\$T\" 2>/dev/null || true
            chmod \"\$MODE\" \"\$T\" 2>/dev/null || true

            mv -f \"\$T\" \"\$DST\" || { echo '❌ IFCv3[remote]: move failed' >&2; exit 1; }
            sync 2>/dev/null || true
        " || {
        echo "❌ remote install failed" >&2
        exit 1
    }
fi

log "🚀 installed $DST_PATH (content:$content_drift owner:$owner_drift group:$group_drift mode:$mode_drift)"
exit 3
