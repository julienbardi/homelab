#!/bin/sh
# install_file_if_changed_v3.1.sh — Dash/Alpine/BusyBox Compatible
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

if [ -z "$SRC_PATH" ] || [ -z "$DST_PATH" ] || [ -z "$OWNER" ] || [ -z "$GROUP" ] || [ -z "$MODE" ]; then
    echo "❌ Usage: SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
    exit 1
fi

PID=$$
: "${TMPDIR:=/tmp}"

# Resolve SSH identity
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
    # Dash-safe command substitution
    SRC_HASH=$(ssh -p "$SRC_PORT" -o BatchMode=yes "$SRC_HOST" "sha256sum '$SRC_PATH'" 2>/dev/null | awk '{print $1}')
    [ -z "$SRC_HASH" ] && SRC_HASH="none"
fi

if [ -z "$SRC_HASH" ]; then
    echo "❌ Failed to calculate source hash for $SRC_PATH" >&2
    exit 1
fi

# --- 2. Destination hash ---
if [ -z "$DST_HOST" ]; then
    DST_HASH=$(sha256sum "$DST_PATH" 2>/dev/null | awk '{print $1}')
    [ -z "$DST_HASH" ] && DST_HASH="none"
else
    # Dash-safe: Ensure the whole block is captured correctly
    DST_HASH=$(ssh -p "$DST_PORT" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o IdentityFile="$SSH_IDENTITY" \
        "$DST_HOST" "sha256sum '$DST_PATH' 2>/dev/null" 2>/dev/null | awk '{print $1}') || DST_HASH="none"
fi

content_drift=0
owner_drift=0
group_drift=0
mode_drift=0

[ "$SRC_HASH" != "$DST_HASH" ] && content_drift=1

# Metadata drift (local only)
if [ -z "$DST_HOST" ]; then
    # Dash-safe stat calls
    dst_owner=""
    dst_group=""
    dst_mode=""

    if [ -e "$DST_PATH" ]; then
        dst_owner=$(stat -c %u "$DST_PATH" 2>/dev/null || echo "$OWNER")
        dst_group=$(stat -c %g "$DST_PATH" 2>/dev/null || echo "$GROUP")
        dst_mode=$(stat -c %a "$DST_PATH" 2>/dev/null || echo "$MODE")
        [ -z "$dst_owner" ] && dst_owner="$OWNER"
        [ -z "$dst_group" ] && dst_group="$GROUP"

        req_owner=$(id -u "$OWNER" 2>/dev/null || echo "$OWNER")
        req_group=$(getent group "$GROUP" | awk -F: '{print $3}' 2>/dev/null || echo "$GROUP")
    fi

    # numeric compare
    [ -n "$dst_owner" ] && [ "$dst_owner" != "$req_owner" ] && owner_drift=1
    [ -n "$dst_group" ] && [ "$dst_group" != "$req_group" ] && group_drift=1

    # normalize modes
    norm_dst_mode=$(echo "$dst_mode" | tr -d '[:space:]' | sed 's/^0*//')
    norm_req_mode=$(echo "$MODE" | tr -d '[:space:]' | sed 's/^0*//')

    [ -z "$norm_dst_mode" ] && norm_dst_mode=0
    [ -z "$norm_req_mode" ] && norm_req_mode=0

    [ "$norm_dst_mode" != "$norm_req_mode" ] && mode_drift=1
fi

if [ "$content_drift" = 0 ] && [ "$owner_drift" = 0 ] && [ "$group_drift" = 0 ] && [ "$mode_drift" = 0 ]; then
    #log "🟢 already up-to-date: $DST_PATH"
    exit 0
fi

#log "🔄 updating $DST_PATH..."

# --- 3. Local buffer ---
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

# --- 4. Install ---
if [ -z "$DST_HOST" ]; then
    DST_DIR=$(dirname "$DST_PATH")
    LOCK="${DST_PATH}.lock"

    mkdir -p "$DST_DIR"

    trap 'rm -rf "$LOCK" "$BUFFER" 2>/dev/null || true' EXIT

    if ! mkdir "$LOCK" 2>/dev/null; then
        echo "❌ lock held: $LOCK" >&2
        rm -f "$BUFFER"
        exit 1
    fi

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
    # Remote install
    IFC_ID="$(date +%s).$$"
    REM_DIR="$(dirname "$DST_PATH")"
    REM_TMP="$REM_DIR/.ifc_v3_${IFC_ID}"

    # Transfer
    if ! ssh -p "$DST_PORT" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        -o IdentityFile="$SSH_IDENTITY" \
        "$DST_HOST" "cat > '$REM_TMP'" < "$BUFFER"; then
        echo "❌ remote transfer failed" >&2
        rm -f "$BUFFER"
        exit 1
    fi

    rm -f "$BUFFER"

    # Remote finalize
    # NOTE: We use double quotes for the outer shell to expand variables,
    # but escape the inner variables for the remote shell.
    if ! ssh -p "$DST_PORT" \
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
        "; then
        echo "❌ remote install failed" >&2
        exit 1
    fi
fi

log "🚀 installed $DST_PATH (content:$content_drift owner:$owner_drift group:$group_drift mode:$mode_drift)"
exit 3