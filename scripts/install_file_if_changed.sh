#!/bin/sh
# install_file_if_changed.sh — idempotent, atomic file installer (local or remote), optimized for Asus Merlin & Ugreen NAS
#
# Usage:
#   install_file_if_changed.sh [-q|--quiet] \
#       SRC_HOST SRC_PORT SRC_PATH \
#       DST_HOST DST_PORT DST_PATH \
#       OWNER GROUP MODE
#
# Semantics:
# - SRC_HOST / DST_HOST may be empty ("") to indicate local execution
# - SRC_PORT / DST_PORT default to 22 when empty
# Options:
#   -q, --quiet     suppress informational output (errors are always shown)
#
# Guarantees:
# - Installs SRC_PATH to DST_PATH only if content differs
# - Ownership and permissions are enforced when content differs
# - Atomic replacement on destination (no partial writes)
# - Correct ownership and permissions applied before activation
# - Safe under concurrent runs
# - Minimal I/O (hash compare, early exit)
# - Works across local ↔ local, local ↔ remote, remote ↔ remote
#
# Exit codes:
#   0  -> Success, destination already up-to-date (no change)
#   3  -> Success, destination was updated
#        (override with CHANGED_EXIT_CODE environment variable)
#   1  -> Failure (invalid arguments, SSH failure, transfer error, or permission error)
#
# Notes:
# - This script must be run as root.
# - SSH access must be non-interactive (key-based).
# ---------------------------------------------------------------------------
# CONTRACT:
# - Exit codes: 0 unchanged, 3 changed, 1 failure
# - No partial writes; destination is replaced atomically
# - Errors are always printed; quiet suppresses info only
# - No environment variables affect behavior except CHANGED_EXIT_CODE
# - Temporary files respect TMPDIR when set, otherwise /tmp
# ---------------------------------------------------------------------------
set -eu
quiet=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		-q|--quiet)
			quiet=1
			shift
			;;
		--)
			shift
			break
			;;
		-*)
			echo "❌ Unknown option: $1" >&2
			exit 1
			;;
		*)
			break
			;;
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

if [ "$(id -u)" -ne 0 ]; then
	echo "❌ install_file_if_changed must be run as root (use sudo)" >&2
	exit 1
fi

if [ -z "$SRC_PATH" ] || [ -z "$DST_PATH" ] || [ -z "$OWNER" ] || [ -z "$GROUP" ] || [ -z "$MODE" ]; then
	echo "❌ Usage: $0 SRC_HOST SRC_PORT SRC_PATH DST_HOST DST_PORT DST_PATH OWNER GROUP MODE" >&2
	exit 1
fi

case "$MODE" in
	[0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
	*)
		echo "❌ Invalid mode: $MODE" >&2
		exit 1
		;;
esac

: "${TMPDIR:=/tmp}"

PID="$$"
TMP_HASH_SRC="$TMPDIR/.ifc_src_hash.$PID"
TMP_HASH_DST="$TMPDIR/.ifc_dst_hash.$PID"
LOCAL_TMP_SRC=""
TMP_HASH_SRC_RAW="$TMP_HASH_SRC.raw"
TMP_HASH_DST_RAW="$TMP_HASH_DST.raw"

trap '
	rm -f "$TMP_HASH_SRC" "$TMP_HASH_DST" \
		  "$TMP_HASH_SRC_RAW" "$TMP_HASH_DST_RAW"
	[ -n "$LOCAL_TMP_SRC" ] && [ "$LOCAL_TMP_SRC" != "$SRC_PATH" ] && rm -f "$LOCAL_TMP_SRC"
' EXIT

# Assumes non-interactive SSH (BatchMode via key auth). Any prompt will cause failure.
# -T disables pseudo-TTY allocation for clean scripting output.
ssh_cmd() {
    _H="$1"; _P="$2"; shift 2
    if [ -z "$_H" ]; then
        "$@"
    else
        if [ -n "$OWNER" ] && [ "$OWNER" != "root" ]; then
            sudo -u "$OWNER" ssh -T -p "$_P" -q \
                -o BatchMode=yes -o ConnectTimeout=5 \
                "$OWNER@$_H" "$@"
        else
            ssh -T -p "$_P" -q \
                -o BatchMode=yes -o ConnectTimeout=5 \
                "$_H" "$@"
        fi
    fi
}

###############################################################################
# Step 1: Parallel hashing
###############################################################################
(
	if [ -z "$SRC_HOST" ]; then
		sha256sum "$SRC_PATH" >"$TMP_HASH_SRC_RAW"
	else
		ssh_cmd "$SRC_HOST" "$SRC_PORT" sha256sum "$SRC_PATH" >"$TMP_HASH_SRC_RAW"
	fi || {
		echo "❌ Failed to hash source: $SRC_PATH" >&2
		exit 1
	}
	awk '{print $1}' "$TMP_HASH_SRC_RAW" >"$TMP_HASH_SRC"
) &
P1=$!

(
	if ssh_cmd "$DST_HOST" "$DST_PORT" test -f "$DST_PATH"; then
		ssh_cmd "$DST_HOST" "$DST_PORT" sha256sum "$DST_PATH" >"$TMP_HASH_DST_RAW" || {
			echo "❌ Failed to hash destination: $DST_PATH" >&2
			exit 1
		}
		awk '{print $1}' "$TMP_HASH_DST_RAW" >"$TMP_HASH_DST"
	else
		: >"$TMP_HASH_DST"
	fi
) &
P2=$!

wait $P1 || exit 1
wait $P2 || exit 1

SRC_HASH=$(cat "$TMP_HASH_SRC")
DST_HASH=$(cat "$TMP_HASH_DST")

[ -z "$SRC_HASH" ] && { echo "❌ Source hash calculation failed" >&2; exit 1; }
[ "$SRC_HASH" = "$DST_HASH" ] && {
	[ "$quiet" -eq 0 ] && echo "⚪ $DST_PATH unchanged" >&2
	exit 0
}
###############################################################################
# Step 2: Transfer preparation
###############################################################################
if [ -z "$SRC_HOST" ]; then
	LOCAL_TMP_SRC="$SRC_PATH"
else
	LOCAL_TMP_SRC="$TMPDIR/.ifc_local_src.$PID"
	scp -P "$SRC_PORT" -q -- "$SRC_HOST:$SRC_PATH" "$LOCAL_TMP_SRC" || {
	echo "❌ Failed to fetch source: $SRC_PATH" >&2
	exit 1
	}
fi

DST_DIR=$(ssh_cmd "$DST_HOST" "$DST_PORT" dirname "$DST_PATH")

ssh_cmd "$DST_HOST" "$DST_PORT" test -d "$DST_DIR" || {
	echo "❌ Destination directory does not exist: $DST_DIR" >&2
	exit 1
}

RND="$(printf '%s' "$PID" | sha256sum | awk '{print substr($1,1,8)}')"
TMP_REMOTE="$DST_DIR/.ifc_tmp.$PID.$RND"

###############################################################################
# Step 3: Upload (pure SSH, no SCP/SFTP)
###############################################################################
if [ -z "$DST_HOST" ]; then
	cp "$LOCAL_TMP_SRC" "$TMP_REMOTE"
else
	# Stream file contents over SSH into a temporary file
	if [ -n "$OWNER" ] && [ "$OWNER" != "root" ]; then
		sudo -u "$OWNER" ssh -T -p "$DST_PORT" -q -o BatchMode=yes -o ConnectTimeout=5 \
			"$OWNER@$DST_HOST" "cat > '$TMP_REMOTE'" < "$LOCAL_TMP_SRC" || {
				echo "❌ Failed to upload file via SSH streaming" >&2
				exit 1
			}
	else
		ssh -T -p "$DST_PORT" -q -o BatchMode=yes -o ConnectTimeout=5 \
			"$DST_HOST" "cat > '$TMP_REMOTE'" < "$LOCAL_TMP_SRC" || {
				echo "❌ Failed to upload file via SSH streaming" >&2
				exit 1
			}
	fi
fi

###############################################################################
# Step 4: Single SSH transaction (atomic perms + move)
###############################################################################
if ! ssh_cmd "$DST_HOST" "$DST_PORT" sh -s <<EOF
chown "$OWNER:$GROUP" "$TMP_REMOTE" &&
chmod "$MODE" "$TMP_REMOTE" &&
mv -f "$TMP_REMOTE" "$DST_PATH"
EOF
then
	ssh_cmd "$DST_HOST" "$DST_PORT" rm -f "$TMP_REMOTE"
	echo "❌ Deployment failed on destination" >&2
	exit 1
fi

[ "$quiet" -eq 0 ] && echo "🔄 $DST_PATH updated" >&2
exit "${CHANGED_EXIT_CODE:-3}"
