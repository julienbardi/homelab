#!/bin/bash
# --------------------------------------------------------------------
# scripts/install_files_if_changed_v2.sh
# --------------------------------------------------------------------
# Vectorized IFC wrapper with batched drift detection.
# If all remote files match all local files ➡️ exit 0 immediately.
# Otherwise ➡️ call install_files_if_changed_v2 (per-file IFC).
# --------------------------------------------------------------------

# 1. Locate and source common.sh
if [ -f "/usr/local/bin/common.sh" ]; then
    source "/usr/local/bin/common.sh"
elif [ -f "$(dirname "$0")/common.sh" ]; then
    source "$(dirname "$0")/common.sh"
else
    echo "❌ Error: common.sh not found." >&2
    exit 1
fi

# 2. Verify the function exists in common.sh
if ! declare -f install_files_if_changed_v2 >/dev/null; then
    echo "❌ Error: Function install_files_if_changed_v2 not defined in common.sh" >&2
    exit 1
fi

# --------------------------------------------------------------------
# 3. Parse arguments
# --------------------------------------------------------------------
VAR_NAME=$1
shift

# Initialize flag variable for safety under set -u
eval "$VAR_NAME=0"

# Remaining args are groups of 9:
# "" "" SRC HOST PORT DST OWNER GROUP MODE
args=("$@")
n=${#args[@]}

if (( n % 9 != 0 )); then
    echo "❌ install_files_if_changed_v2.sh: argument count not divisible by 9" >&2
    exit 1
fi

# --------------------------------------------------------------------
# 4. Build local and remote hash lists
# --------------------------------------------------------------------
local_hashes=()
remote_targets=()

i=0
while (( i < n )); do
    src="${args[i+2]}"
    host="${args[i+3]}"
    port="${args[i+4]}"
    dst="${args[i+5]}"

    # Local hash
    if [ ! -f "$src" ]; then
        echo "❌ Missing local file: $src" >&2
        exit 1
    fi
    local_hashes+=( "$(sha256sum "$src" | awk '{print $1}')" )

    # Remote target path
    remote_targets+=( "$dst" )

    i=$(( i + 9 ))
done

LOCAL_COMBINED_HASH="$(
    printf '%s\n' "${local_hashes[@]}" | sort | sha256sum | awk '{print $1}'
)"

# --------------------------------------------------------------------
# 5. Compute remote combined hash in ONE SSH call
# --------------------------------------------------------------------
# All HOST/PORT are identical by contract, so use the first group.
if (( ${#args[@]} < 5 )); then
    echo "❌ No file tuples passed to vectorized IFC" >&2
    exit 1
fi

first_host="${args[3]}"
first_port="${args[4]}"

# Default SSH port if empty
if [ -z "$first_port" ]; then
    first_port=22
fi

# Build remote hash script
remote_script="cd / && ("
for dst in "${remote_targets[@]}"; do
    remote_script+="[ -f \"$dst\" ] && sha256sum \"$dst\" | awk '{print \$1}'; "
done
remote_script+=") | sort | sha256sum | awk '{print \$1}'"

REMOTE_COMBINED_HASH="$(
    ssh -p "$first_port" \
        -o PreferredAuthentications=publickey \
        -o PubkeyAuthentication=yes \
        -o PasswordAuthentication=no \
        "$first_host" "$remote_script" 2>/dev/null
)"

# --------------------------------------------------------------------
# 6. Fast-path: skip IFC if hashes match
# --------------------------------------------------------------------
if [ "$LOCAL_COMBINED_HASH" = "$REMOTE_COMBINED_HASH" ]; then
    # No drift ➡️ no file changed
    exit 0
fi

# --------------------------------------------------------------------
# 7. Slow-path: call vectorized IFC engine
# --------------------------------------------------------------------
install_files_if_changed_v2 "$VAR_NAME" "$@"

# If any file changed, exit 3
if [ "${!VAR_NAME:-0}" -eq 1 ]; then
    exit 3
fi

exit 0
